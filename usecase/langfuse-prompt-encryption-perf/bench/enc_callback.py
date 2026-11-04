#!/usr/bin/env python3
"""enc_callback.py — a Langfuse EE ingestion "masking" callback that ENCRYPTS prompt fields instead.

Langfuse's worker POSTs each OTLP trace request (JSON) to LANGFUSE_INGESTION_MASKING_CALLBACK_URL
before writing to ClickHouse and stores whatever comes back (same structure, values changed).
This service replaces the string values of the input/output attributes with ciphertext:

  POST /local       envelope: data key unwrapped once from OpenBao at start, AES-256-GCM in process
  POST /kms_batch   OpenBao Transit encrypts every value of the request in one call
  POST /kms_row     one Transit call per value
  POST /kms_row5    one Transit call per value + 5 ms simulated round trip per call
  GET  /health

Same ciphertext formats as clickhouse/user_scripts/prompt_crypto.py ("v1:…" / "vault:v1:…").
"""
import base64
import http.client
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

SECRETS = "/etc/prompt-enc"
KEYS = {"langfuse.observation.input", "langfuse.observation.output",
        "langfuse.trace.input", "langfuse.trace.output"}
TOKEN = open(f"{SECRETS}/bao-token").read().strip()
_local = threading.local()


def kms(path: str, body: dict, rtt: float = 0.0) -> dict:
    conn = getattr(_local, "conn", None)
    for attempt in (1, 2):
        try:
            if conn is None:
                conn = _local.conn = http.client.HTTPConnection("openbao", 8200, timeout=30)
            if rtt:
                time.sleep(rtt)
            conn.request("POST", f"/v1/{path}", body=json.dumps(body),
                         headers={"X-Vault-Token": TOKEN, "Content-Type": "application/json"})
            resp = conn.getresponse()
            data = resp.read()
            if resp.status != 200:
                raise RuntimeError(f"OpenBao HTTP {resp.status}: {data[:200]!r}")
            return json.loads(data)["data"]
        except (http.client.HTTPException, ConnectionError, OSError):
            conn = _local.conn = None
            if attempt == 2:
                raise


AES = AESGCM(base64.b64decode(kms("transit/decrypt/prompt",
                                  {"ciphertext": open(f"{SECRETS}/dek.wrapped").read().strip()})["plaintext"]))


def enc_local(v: str) -> str:
    nonce = os.urandom(12)
    return "v1:" + base64.b64encode(nonce + AES.encrypt(nonce, v.encode(), None)).decode()


def targets(node, out):
    """Collect the attribute value dicts whose key is an input/output field."""
    if isinstance(node, dict):
        if node.get("key") in KEYS and isinstance(node.get("value"), dict) and "stringValue" in node["value"]:
            out.append(node["value"])
        for v in node.values():
            targets(v, out)
    elif isinstance(node, list):
        for v in node:
            targets(v, out)
    return out


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        self._send(200, b'{"status":"ok"}')

    def do_POST(self):  # noqa: N802
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0) or 0)) or b"{}")
        vals = [v for v in targets(payload, []) if v["stringValue"]]
        mode = self.path.strip("/")
        try:
            if mode == "local":
                for v in vals:
                    v["stringValue"] = enc_local(v["stringValue"])
            elif mode == "kms_batch" and vals:
                items = [{"plaintext": base64.b64encode(v["stringValue"].encode()).decode()} for v in vals]
                res = kms("transit/encrypt/prompt", {"batch_input": items})["batch_results"]
                for v, r in zip(vals, res):
                    v["stringValue"] = r["ciphertext"]
            elif mode in ("kms_row", "kms_row5"):
                rtt = 0.005 if mode == "kms_row5" else 0.0
                for v in vals:
                    pt = base64.b64encode(v["stringValue"].encode()).decode()
                    v["stringValue"] = kms("transit/encrypt/prompt", {"plaintext": pt}, rtt)["ciphertext"]
        except Exception as e:  # noqa: BLE001 — a failed callback must not return plaintext
            sys.stderr.write(f"[enc] {mode} failed: {e}\n")
            self._send(500, b'{"error":"encryption failed"}')
            return
        self._send(200, json.dumps(payload, ensure_ascii=False).encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("enc-callback on :3100 (POST /local /kms_batch /kms_row /kms_row5)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 3100), Handler).serve_forever()
