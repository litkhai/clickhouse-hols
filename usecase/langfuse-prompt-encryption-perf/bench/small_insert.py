#!/usr/bin/env python3
"""small_insert.py — open-loop load of Langfuse-sized inserts against ClickHouse over HTTP.

    small_insert.py <table> <traces_per_second> <seconds> <payload.jsonl> [workers]

Langfuse's worker writes events_full with small synchronous `INSERT … FORMAT JSONEachRow`
batches (1–6 rows each in the langfuse-hols stack's query log). Here one insert = one trace =
4 observations, sent on a fixed schedule (open loop): if inserts get slower, latency grows and
the achieved rate falls behind, instead of the generator politely slowing down.

payload.jsonl: one JSON array per line, the 4 rows of one trace (taken from bench.ev_plain).
Prints one TSV line: target_tps achieved_tps inserts errors p50_ms p95_ms p99_ms max_ms late_ms_p95
(late = how far behind its scheduled start an insert began, a sign the client pool was saturated).
"""
import base64
import json
import os
import queue
import sys
import threading
import time
import urllib.request

table, tps, seconds, payload_path = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
workers = int(sys.argv[5]) if len(sys.argv) > 5 else 64
url = "http://127.0.0.1:18124/?query=" + urllib.parse.quote(f"INSERT INTO bench.{table} FORMAT JSONEachRow")
auth = "Basic " + base64.b64encode(f"bench:{os.environ['CH_PASSWORD']}".encode()).decode()

bodies = []
with open(payload_path) as f:
    for line in f:
        rows = json.loads(line)
        bodies.append("\n".join(json.dumps(r, ensure_ascii=False) for r in rows).encode())

tasks: "queue.Queue" = queue.Queue()
lat, late, errors = [], [], [0]
lock = threading.Lock()


def worker() -> None:
    while True:
        item = tasks.get()
        if item is None:
            return
        scheduled, body = item
        start = time.perf_counter()
        try:
            req = urllib.request.Request(url, data=body, method="POST",
                                         headers={"Authorization": auth, "Content-Type": "application/x-ndjson"})
            urllib.request.urlopen(req, timeout=120).read()
            ok = True
        except Exception as e:  # noqa: BLE001 — count and keep going
            ok = False
            if errors[0] < 3:
                sys.stderr.write(f"insert error: {e}\n")
        end = time.perf_counter()
        with lock:
            if ok:
                lat.append((end - start) * 1000)
                late.append((start - scheduled) * 1000)
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
    tasks.put((at, bodies[i % len(bodies)]))
for _ in threads:
    tasks.put(None)
for t in threads:
    t.join()
wall = time.perf_counter() - t0


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100 * len(xs)))] if xs else float("nan")


print(f"{tps:g}\t{len(lat) / wall:.1f}\t{len(lat)}\t{errors[0]}\t{pct(lat, 50):.1f}\t{pct(lat, 95):.1f}"
      f"\t{pct(lat, 99):.1f}\t{max(lat) if lat else float('nan'):.1f}\t{pct(late, 95):.1f}")
