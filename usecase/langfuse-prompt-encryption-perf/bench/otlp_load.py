#!/usr/bin/env python3
"""otlp_load.py — open-loop OTLP/HTTP (JSON) load into Langfuse, one trace = 4 spans per request.

    otlp_load.py <run_id> <traces_per_second> <seconds> <payload.jsonl> [workers]

Env: LANGFUSE_HOST (default http://localhost:3000), LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY.
Spans reuse the bench payload (bench.ev_plain rows): input/output, type, model, usage. Every span
gets start time = send time and the observation metadata `bench_run = <run_id>`, so ClickHouse can
later report end-to-end lag (events_full.created_at − start_time) and how many rows arrived.
Prints: target_tps achieved_tps requests http_errors accept_p50_ms accept_p95_ms accept_p99_ms
"""
import base64
import json
import os
import queue
import secrets
import sys
import threading
import time
import urllib.request

run_id, tps, seconds, payload_path = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
workers = int(sys.argv[5]) if len(sys.argv) > 5 else 64
host = os.environ.get("LANGFUSE_HOST", "http://localhost:3000")
auth = "Basic " + base64.b64encode(
    f"{os.environ['LANGFUSE_PUBLIC_KEY']}:{os.environ['LANGFUSE_SECRET_KEY']}".encode()).decode()
url = f"{host}/api/public/otel/v1/traces"

with open(payload_path) as f:
    traces = [json.loads(line) for line in f]

TYPE = {"SPAN": "span", "GENERATION": "generation", "TOOL": "tool"}


def attr(k, v):
    if isinstance(v, int):
        return {"key": k, "value": {"intValue": str(v)}}
    return {"key": k, "value": {"stringValue": str(v)}}


def build(rows) -> bytes:
    trace_id = secrets.token_hex(16)
    ids = [secrets.token_hex(8) for _ in rows]
    now = time.time_ns()
    spans = []
    for i, r in enumerate(rows):
        a = [attr("langfuse.observation.type", TYPE.get(r["type"], "span")),
             attr("langfuse.observation.input", r["input"]),
             attr("langfuse.observation.output", r["output"]),
             attr("langfuse.observation.metadata.bench_run", run_id),
             attr("langfuse.trace.name", r["trace_name"]),
             attr("user.id", r["user_id"]),
             attr("session.id", r["session_id"])]
        if r["type"] == "GENERATION":
            a += [attr("langfuse.observation.model.name", r["provided_model_name"]),
                  attr("gen_ai.usage.input_tokens", int(r["usage_details"].get("input", 0))),
                  attr("gen_ai.usage.output_tokens", int(r["usage_details"].get("output", 0)))]
        spans.append({"traceId": trace_id, "spanId": ids[i], "parentSpanId": "" if i == 0 else ids[0],
                      "name": r["name"], "kind": 1, "startTimeUnixNano": str(now),
                      "endTimeUnixNano": str(now + 1_000_000), "attributes": a, "status": {}})
    body = {"resourceSpans": [{"resource": {"attributes": [attr("service.name", "prompt-enc-bench")]},
                               "scopeSpans": [{"scope": {"name": "langfuse-sdk", "version": "4.0.0"},
                                               "spans": spans}]}]}
    return json.dumps(body, ensure_ascii=False).encode()


tasks: "queue.Queue" = queue.Queue()
lat, errors, lock = [], [0], threading.Lock()


def worker() -> None:
    while True:
        item = tasks.get()
        if item is None:
            return
        body = build(item)
        start = time.perf_counter()
        try:
            req = urllib.request.Request(url, data=body, method="POST",
                                         headers={"Authorization": auth, "Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=60).read()
            ok = True
        except Exception as e:  # noqa: BLE001
            ok = False
            if errors[0] < 3:
                sys.stderr.write(f"otlp error: {e}\n")
        with lock:
            if ok:
                lat.append((time.perf_counter() - start) * 1000)
            else:
                errors[0] += 1


threads = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
for t in threads:
    t.start()
n = int(tps * seconds)
t0 = time.perf_counter()
for i in range(n):
    at = t0 + i / tps
    now = time.perf_counter()
    if at > now:
        time.sleep(at - now)
    tasks.put(traces[i % len(traces)])
for _ in threads:
    tasks.put(None)
for t in threads:
    t.join()
wall = time.perf_counter() - t0


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100 * len(xs)))] if xs else float("nan")


print(f"{tps:g}\t{len(lat) / wall:.1f}\t{len(lat)}\t{errors[0]}\t{pct(lat, 50):.1f}\t{pct(lat, 95):.1f}\t{pct(lat, 99):.1f}")
