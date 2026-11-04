#!/usr/bin/env python3
"""prompt_crypto.py — executable UDF body for encrypting / decrypting Langfuse prompt fields.

    prompt_crypto.py <enc|dec> <local|kms_batch|kms_row> [rtt_ms]

ClickHouse runs it as an `executable_pool` function with `send_chunk_header` = true and
format TabSeparated: each chunk starts with a line holding the row count, then one value per
line. We answer with exactly one line per row.

Modes
  local      envelope encryption: at start the process asks the KMS (OpenBao Transit) ONCE to
             unwrap the data key (DEK), then encrypts / decrypts with AES-256-GCM in process.
             Output: "v1:" + base64(nonce12 || ciphertext || tag16).
  kms_batch  the KMS itself encrypts / decrypts: one Transit call per batch of up to
             BATCH_ROWS rows / BATCH_BYTES bytes (`batch_input`). Output: Transit's "vault:v1:…".
  kms_row    one Transit call per row — what "call the key service for every value" costs.

rtt_ms adds that many milliseconds of sleep per KMS call, to stand for the network round trip
to a managed KMS (the local OpenBao answers in well under a millisecond). It is a simulation.

The value we encrypt is the line exactly as ClickHouse sent it (TSV-escaped); decrypting
returns the same bytes, which ClickHouse unescapes, so the round trip is exact. Empty values
stay empty.
"""
import base64
import http.client
import json
import os
import sys
import time

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

OP, MODE = sys.argv[1], sys.argv[2]
RTT = float(sys.argv[3]) / 1000.0 if len(sys.argv) > 3 else 0.0
SECRETS = "/etc/prompt-enc"
KEY_NAME = "prompt"
BATCH_ROWS, BATCH_BYTES = 256, 4 * 1024 * 1024

with open(f"{SECRETS}/bao-token") as f:
    TOKEN = f.read().strip()
_conn = None
kms_calls = 0


def kms(path: str, body: dict) -> dict:
    """POST to OpenBao over one kept-alive connection; reconnect once on a dropped socket."""
    global _conn, kms_calls
    data = json.dumps(body)
    for attempt in (1, 2):
        try:
            if _conn is None:
                _conn = http.client.HTTPConnection("openbao", 8200, timeout=30)
            if RTT:
                time.sleep(RTT)
            _conn.request("POST", f"/v1/{path}", body=data,
                          headers={"X-Vault-Token": TOKEN, "Content-Type": "application/json"})
            resp = _conn.getresponse()
            payload = resp.read()
            kms_calls += 1
            if resp.status != 200:
                raise RuntimeError(f"OpenBao {path}: HTTP {resp.status} {payload[:200]!r}")
            return json.loads(payload)["data"]
        except (http.client.HTTPException, ConnectionError, OSError):
            _conn = None
            if attempt == 2:
                raise


if MODE == "local":
    with open(f"{SECRETS}/dek.wrapped") as f:
        wrapped = f.read().strip()
    dek = base64.b64decode(kms(f"transit/decrypt/{KEY_NAME}", {"ciphertext": wrapped})["plaintext"])
    aes = AESGCM(dek)


def enc_local(v: bytes) -> bytes:
    nonce = os.urandom(12)
    return b"v1:" + base64.b64encode(nonce + aes.encrypt(nonce, v, None))


def dec_local(v: bytes) -> bytes:
    raw = base64.b64decode(v[3:])
    return aes.decrypt(raw[:12], raw[12:], None)


def kms_many(values: list) -> list:
    """Encrypt or decrypt a list of non-empty values with one Transit call."""
    if OP == "enc":
        items = [{"plaintext": base64.b64encode(v).decode()} for v in values]
        out = kms(f"transit/encrypt/{KEY_NAME}", {"batch_input": items})["batch_results"]
        return [r["ciphertext"].encode() for r in out]
    items = [{"ciphertext": v.decode()} for v in values]
    out = kms(f"transit/decrypt/{KEY_NAME}", {"batch_input": items})["batch_results"]
    return [base64.b64decode(r["plaintext"]) for r in out]


def process(rows: list) -> list:
    out = [b""] * len(rows)
    idx = [i for i, v in enumerate(rows) if v]
    if MODE == "local":
        fn = enc_local if OP == "enc" else dec_local
        for i in idx:
            out[i] = fn(rows[i])
    elif MODE == "kms_row":
        for i in idx:
            out[i] = kms_many([rows[i]])[0]
    else:  # kms_batch
        start, size = 0, 0
        for k, i in enumerate(idx):
            size += len(rows[i])
            if k - start + 1 >= BATCH_ROWS or size >= BATCH_BYTES or k == len(idx) - 1:
                chunk = idx[start:k + 1]
                for j, res in zip(chunk, kms_many([rows[j] for j in chunk])):
                    out[j] = res
                start, size = k + 1, 0
    return out


def main() -> None:
    stdin, stdout = sys.stdin.buffer, sys.stdout.buffer
    while True:
        header = stdin.readline()
        if not header:
            break
        n = int(header)
        rows = [stdin.readline().rstrip(b"\n") for _ in range(n)]
        stdout.write(b"\n".join(process(rows)) + (b"\n" if n else b""))
        stdout.flush()


if __name__ == "__main__":
    main()
