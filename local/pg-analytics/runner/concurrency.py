"""Phase 3: closed-loop concurrency on Q6 (L1) and Q3 (L3).

    python runner/concurrency.py --sf 10 [--clients 1,4,8,16] [--seconds 60]

Each client holds its own session and re-issues the query as soon as the
previous one returns. The window is warm (one untimed warm-up per client).
Reports QPS, p50/p95/p99 and pg-main's average busy cores over the window;
the last number is the one that says when analytics starts eating the OLTP node.
Appends to results/sf<N>/concurrency.csv.
"""
import argparse
import csv
import os
import statistics
import threading
import time

import psycopg

from common import (C_PG_MAIN, LAB, PATH_CONTAINERS, PATH_ENGINE, cgroup_cpu_s, connect,
                    set_active)
from bench import SCHEMA, query_text


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))] if xs else None


def window(path, qid, clients, seconds, timeout):
    sql = query_text(qid)
    lat, errors, stop = [], [0], threading.Event()
    lock = threading.Lock()
    ready = threading.Barrier(clients + 1)

    def worker():
        c = connect(path)
        c.execute(f"SET search_path = {SCHEMA[(path, 'D1')]}, public")
        c.execute(f"SET statement_timeout = '{timeout}s'")
        c.execute(sql).fetchall()  # warm-up
        ready.wait()
        while not stop.is_set():
            t0 = time.perf_counter()
            try:
                c.execute(sql).fetchall()
                with lock:
                    lat.append((time.perf_counter() - t0) * 1000)
            except psycopg.Error:
                errors[0] += 1
                try:
                    c.close()
                except Exception:
                    pass
                c = connect(path)
                c.execute(f"SET search_path = {SCHEMA[(path, 'D1')]}, public")
        c.close()

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(clients)]
    for t in threads:
        t.start()
    ready.wait()
    names = PATH_CONTAINERS[path]
    cpu0 = {n: cgroup_cpu_s(n) for n in names}
    t0 = time.time()
    time.sleep(seconds)
    stop.set()
    elapsed = time.time() - t0
    cpu = {n: (cgroup_cpu_s(n) - cpu0[n]) / elapsed for n in names}
    for t in threads:
        t.join(timeout=timeout + 30)
    return {
        "path": path, "query_id": qid, "clients": clients, "seconds": round(elapsed, 1),
        "completed": len(lat), "errors": errors[0], "qps": round(len(lat) / elapsed, 2),
        "p50_ms": round(pct(lat, 50), 1) if lat else "", "p95_ms": round(pct(lat, 95), 1) if lat else "",
        "p99_ms": round(pct(lat, 99), 1) if lat else "",
        "mean_ms": round(statistics.mean(lat), 1) if lat else "",
        "pg_main_busy_cores": round(cpu[C_PG_MAIN], 2) if C_PG_MAIN in cpu else "",
        "engine_busy_cores": round(cpu[PATH_ENGINE[path]], 2),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sf", type=int, required=True)
    ap.add_argument("--paths", default="A,B,B2,C")
    ap.add_argument("--queries", default="q06,q03")
    ap.add_argument("--clients", default="1,4,8,16")
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--timeout", type=int, default=int(os.environ.get("QUERY_TIMEOUT_S", 300)))
    a = ap.parse_args()
    out = LAB / "results" / f"sf{a.sf}" / "concurrency.csv"
    new = not out.exists()
    with open(out, "a", newline="") as fh:
        w = None
        for path in a.paths.split(","):
            set_active(path)
            for qid in a.queries.split(","):
                for n in map(int, a.clients.split(",")):
                    r = window(path, qid, n, a.seconds, a.timeout)
                    r["sf"] = a.sf
                    print(r, flush=True)
                    if w is None:
                        w = csv.DictWriter(fh, fieldnames=list(r))
                        if new:
                            w.writeheader()
                    w.writerow(r)
                    fh.flush()


if __name__ == "__main__":
    main()
