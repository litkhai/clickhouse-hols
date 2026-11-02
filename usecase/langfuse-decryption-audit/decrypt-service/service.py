#!/usr/bin/env python3
"""decrypt-service — the only path from a ciphertext field in Langfuse to plaintext.

POST /decrypt  {"trace_id": "...", "field": "input" | "output", "reason": "..."}
Authorization: Bearer <the user's access token from the company IdP>

1. No bearer token -> 401. No reason -> 400. Both are logged.
2. Reads the field from the Langfuse public API with the service's project key. A field is
   `enc:<key name>:vault:v<n>:...` (OpenBao Transit ciphertext, prefixed with its key).
3. Logs in to OpenBao with the USER's token (auth/jwt/login, role reader-<key name>). OpenBao
   validates the JWT against the IdP and checks the user's group; the service has no standing
   OpenBao token and cannot decrypt on its own.
4. Decrypts with the user's OpenBao token, sending X-Request-Id, which OpenBao's audit log keeps
   in clear. Revokes the user's OpenBao token afterwards.
5. Writes an `attempt` row to the ClickHouse audit table (INSERT-only user) before asking OpenBao to
   decrypt, and one outcome row per request before answering. If either write fails the plaintext is
   not returned (503); if the attempt row fails, OpenBao is never asked: no trail, no decryption.

Standard library only. Not a production service: no TLS, no rate limits, one thread per request.
"""
import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BAO = os.environ["BAO_ADDR"]
LF = os.environ["LANGFUSE_HOST"]
LF_AUTH = "Basic " + base64.b64encode(f"{os.environ['LANGFUSE_PUBLIC_KEY']}:{os.environ['LANGFUSE_SECRET_KEY']}".encode()).decode()
AUDIT = os.environ["AUDIT_URL"]
AUDIT_AUTH = "Basic " + base64.b64encode(f"{os.environ['AUDIT_USER']}:{os.environ['AUDIT_PASSWORD']}".encode()).decode()


def call(method, url, body=None, headers=None, timeout=15):
    """→ (status, parsed JSON or text)"""
    data = json.dumps(body).encode() if isinstance(body, (dict, list)) else body
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw, status = r.read(), r.status
    except urllib.error.HTTPError as e:
        raw, status = e.read(), e.code
    try:
        return status, json.loads(raw or b"null")
    except ValueError:
        return status, raw.decode("utf-8", "replace")


def claimed_user(token):
    """The username the token CLAIMS, unverified — only for logging refusals before OpenBao checks it."""
    try:
        payload = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))).get("preferred_username", "")
    except Exception:
        return "unparseable"


def audit(row):
    line = json.dumps(row) + "\n"
    q = urllib.parse.quote("INSERT INTO audit.decrypt_events FORMAT JSONEachRow")
    try:
        status, _ = call("POST", f"{AUDIT}/?query={q}", line.encode(), {"Authorization": AUDIT_AUTH}, timeout=5)
        return status == 200
    except Exception:
        return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # no plaintext or tokens in container logs
        pass

    def reply(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(200, {"ok": True}) if self.path == "/health" else self.reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/decrypt":
            return self.reply(404, {"error": "not found"})
        rid = str(uuid.uuid4())
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            req = {}
        row = {"request_id": rid, "user": "", "claimed_user": "", "client_ip": self.client_address[0],
               "trace_id": str(req.get("trace_id", "")), "field": str(req.get("field", "input")),
               "key_name": "", "reason": str(req.get("reason", "")).strip(), "outcome": "", "detail": ""}

        def finish(status, outcome, detail, payload=None):
            row["outcome"], row["detail"] = outcome, detail[:500]
            if not audit(row):
                return self.reply(503, {"request_id": rid, "error": "audit store unavailable; nothing decrypted"})
            return self.reply(status, {"request_id": rid, "outcome": outcome, **(payload or {"detail": detail})})

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return finish(401, "unauthenticated", "no bearer token")
        jwt = auth[len("Bearer "):]
        row["claimed_user"] = claimed_user(jwt)
        if len(row["reason"]) < 5:
            return finish(400, "reason_missing", "a reason (5+ characters) is required")
        if row["field"] not in ("input", "output"):
            return finish(400, "bad_request", "field must be input or output")

        q = urllib.parse.urlencode({"traceId": row["trace_id"], "fields": "core,io"})
        status, obs = call("GET", f"{LF}/api/public/v2/observations?{q}", headers={"Authorization": LF_AUTH})
        values = [o.get(row["field"]) for o in (obs or {}).get("data", [])] if status == 200 and isinstance(obs, dict) else []
        value = next((v for v in values if isinstance(v, str) and v.startswith("enc:")), None)
        if value is None:
            return finish(404, "not_found", f"no encrypted {row['field']} for this trace (Langfuse HTTP {status})")
        _, key, ciphertext = value.split(":", 2)
        row["key_name"] = key

        status, login = call("POST", f"{BAO}/v1/auth/jwt/login", {"role": f"reader-{key}", "jwt": jwt}, {"X-Request-Id": rid})
        if status != 200:
            errs = "; ".join((login or {}).get("errors", [])) if isinstance(login, dict) else str(login)
            return finish(403, "denied", f"OpenBao login refused: {errs}")
        bao_token = login["auth"]["client_token"]
        meta = login["auth"].get("metadata") or {}
        row["user"] = meta.get("username") or login["auth"].get("display_name", "")
        # Write the intent before decrypting: if the trail cannot be written, OpenBao is never asked.
        if not audit({**row, "outcome": "attempt", "detail": "about to decrypt"}):
            call("POST", f"{BAO}/v1/auth/token/revoke-self", {}, {"X-Vault-Token": bao_token})
            return self.reply(503, {"request_id": rid, "error": "audit store unavailable; nothing decrypted"})
        try:
            status, dec = call("POST", f"{BAO}/v1/transit/decrypt/{key}", {"ciphertext": ciphertext},
                               {"X-Vault-Token": bao_token, "X-Request-Id": rid})
        finally:
            call("POST", f"{BAO}/v1/auth/token/revoke-self", {}, {"X-Vault-Token": bao_token})
        if status != 200:
            errs = "; ".join((dec or {}).get("errors", [])) if isinstance(dec, dict) else str(dec)
            return finish(403, "denied", f"OpenBao decrypt refused: {errs}")
        plaintext = base64.b64decode(dec["data"]["plaintext"]).decode("utf-8", "replace")
        return finish(200, "success", "decrypted", {"user": row["user"], "plaintext": plaintext})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8095), Handler).serve_forever()
