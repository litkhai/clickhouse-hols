"""Phase 2: single-query benchmark matrix, one path at a time.

    python runner/bench.py --sf 10                       # A, B, C · all queries · per-node
    python runner/bench.py --sf 10 --paths C --resource-mode equal-total
    python runner/bench.py --sf 1 --queries q06,c5 --iters 2
    python runner/bench.py --sf 10 --dims D1 --warm-only --iters 3   # what run-all.sh does

For every (path, query, dimension scenario): restart the path's engines with
empty caches, run once cold, then WARM_ITERS times warm, then EXPLAIN once.
Every row is compared with path A's result hash; a mismatch voids the timing.
Rows are appended to results/sf<N>/bench.csv; plans go to results/sf<N>/plans/.
"""
import argparse
import csv
import datetime as dt
import json
import os
import pathlib
import time
import uuid

import psycopg

from common import (C_CH, C_PG_MAIN, LAB, Probe, classify_pushdown, connect, make_cold,
                    result_hash, set_active, set_cpus, versions)

TIERS = {
    "L1": ["q01", "q06", "c1"],
    "L2": ["c2", "c3"],
    "L3": ["q03", "q05", "q09", "q10"],
    "L4": ["q17", "q18", "q20", "q21", "c4"],
    "L5": ["c5", "c6", "c7"],
}
# D2 (dimensions in heap only) only changes queries that touch a dimension
D2_QUERIES = {"q03", "q05", "q09", "q10", "q17", "q18", "q20", "q21"}
SCHEMA = {("A", "D1"): "a_d1", ("A", "D2"): "a_d2", ("B", "D1"): "b_d1",
          ("B", "D2"): "b_d2", ("B2", "D1"): "b_d1", ("B2", "D2"): "b_d2", ("C", "D1"): "c_d1", ("C", "D2"): "c_d2"}
FIELDS = ["run_id", "ts", "path", "sf", "dim_scenario", "tier", "query_id", "run_type", "iter",
          "latency_ms", "status", "rows", "result_hash", "hash_match", "pushdown",
          "pg_main_cpu_s", "pg_main_pgduck_cpu_s", "pg_main_peak_mem_mb", "engine_cpu_s",
          "engine_peak_mem_mb", "s3_bytes_read", "s3_requests", "resource_mode", "versions_json",
          "error"]


def query_text(qid):
    sub = "tpch" if qid.startswith("q") else "custom"
    return (LAB / "queries" / sub / f"{qid}.sql").read_text()


def tier_of(qid):
    return next(t for t, qs in TIERS.items() if qid in qs)


def items(selected, dims):
    for tier, qs in TIERS.items():
        for q in qs:
            if selected and q not in selected:
                continue
            if "D1" in dims:
                yield tier, q, "D1"
            if "D2" in dims and q in D2_QUERIES:
                yield tier, q, "D2"


# pg_clickhouse's default session settings plus one join-order knob: with no
# row estimates for Iceberg tables, ClickHouse's `auto` never swaps the build
# side, so the biggest table ends up as the hash-join build side.
JOIN_SWAP = ("join_use_nulls 1, group_by_use_nulls 1, final 1, transform_null_in 0, "
             "query_plan_join_swap_table 1")


def session(path, dim, timeout_s, mode="per-node"):
    c = connect(path)
    c.execute(f"SET search_path = {SCHEMA[(path, dim)]}, public")
    c.execute(f"SET statement_timeout = '{timeout_s}s'")
    if path == "C" and mode == "join-swap":
        c.execute(f"SET pg_clickhouse.session_settings = '{JOIN_SWAP}'")
    return c


def run_once(conn, path, sql):
    """Execute and fully fetch one query inside a Probe."""
    status, rows, h, err = "ok", 0, "", ""
    with Probe(path) as p:
        try:
            cur = conn.execute(sql)
            data = cur.fetchall()
            rows, h = len(data), result_hash(data)
        except psycopg.errors.QueryCanceled:
            status = "DNF"
        except (psycopg.OperationalError, psycopg.InterfaceError) as e:
            status, err = "crash", str(e).splitlines()[0][:300]
        except psycopg.Error as e:
            status, err = "error", str(e).splitlines()[0][:300]
    return status, rows, h, err, p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sf", type=int, required=True)
    ap.add_argument("--paths", default="A,B,B2,C")
    ap.add_argument("--queries", default="")
    ap.add_argument("--iters", type=int, default=int(os.environ.get("WARM_ITERS", 5)))
    ap.add_argument("--timeout", type=int, default=int(os.environ.get("QUERY_TIMEOUT_S", 300)))
    ap.add_argument("--resource-mode", choices=["per-node", "equal-total", "join-swap"], default="per-node")
    ap.add_argument("--dims", default="D1,D2", help="dimension placements to run")
    ap.add_argument("--warm-only", action="store_true",
                    help="no engine restart per query: one untimed warm-up, then --iters warm runs")
    args = ap.parse_args()
    selected = set(filter(None, args.queries.split(",")))

    out = LAB / "results" / f"sf{args.sf}"
    (out / "plans").mkdir(parents=True, exist_ok=True)
    ref_file = out / "reference_hashes.json"
    refs = json.loads(ref_file.read_text()) if ref_file.exists() else {}
    csv_path = out / "bench.csv"
    new = not csv_path.exists()
    fh = open(csv_path, "a", newline="")
    w = csv.DictWriter(fh, fieldnames=FIELDS)
    if new:
        w.writeheader()
    run_id = uuid.uuid4().hex[:8]
    engine_cpus = float(os.environ.get("ENGINE_CPUS", 4))

    for path in args.paths.split(","):
        set_active(path)
        if path == "C" and args.resource_mode == "equal-total":
            set_cpus(C_PG_MAIN, engine_cpus / 2)
            set_cpus(C_CH, engine_cpus / 2)
        vers = json.dumps(versions(), separators=(",", ":"))
        for tier, qid, dim in items(selected, args.dims.split(",")):
            sql = query_text(qid)
            key = f"{qid}/{dim}"
            if not args.warm_only:
                make_cold(path)
            conn = session(path, dim, args.timeout, args.resource_mode)
            results = []
            for i in range(args.iters + 1):
                status, nrows, h, err, p = run_once(conn, path, sql)
                kind = "cold" if i == 0 else "warm"
                if args.warm_only and i == 0:
                    kind = "warmup"  # untimed in the report; still hashed and checked
                if status == "crash":  # engine died (OOM kill): reconnect for the record
                    try:
                        conn.close()
                    except Exception:
                        pass
                    time.sleep(5)
                    set_active(path)
                    conn = session(path, dim, args.timeout, args.resource_mode)
                if path == "A" and status == "ok" and i == 0:
                    refs[key] = h
                    ref_file.write_text(json.dumps(refs, indent=1, sort_keys=True))
                if path == "A":
                    match = "ref" if status == "ok" else "n/a"
                elif key not in refs or status != "ok":
                    match = "n/a"
                else:
                    match = "yes" if refs[key] == h else "NO"
                results.append((status, match))
                row = {"run_id": run_id, "ts": dt.datetime.now().isoformat(timespec="seconds"),
                       "path": path, "sf": args.sf, "dim_scenario": dim, "tier": tier,
                       "query_id": qid, "run_type": kind, "iter": i,
                       "latency_ms": round(p.latency_ms, 1), "status": status, "rows": nrows,
                       "result_hash": h, "hash_match": match, "pushdown": "",
                       "resource_mode": args.resource_mode, "versions_json": vers,
                       "error": err, **p.m}
                w.writerow(row)
                fh.flush()
                print(f"[{path} sf{args.sf} {dim} {qid} {row['run_type']}#{i}] "
                      f"{status} {p.latency_ms:9.1f} ms rows={nrows} match={match} "
                      f"engine_cpu={p.m['engine_cpu_s']}s pg_cpu={p.m['pg_main_cpu_s']}s "
                      f"s3={p.m['s3_bytes_read'] / 2**20:.1f}MiB {err}", flush=True)
                if status in ("DNF", "error", "crash"):
                    break  # no point repeating a timeout or a failure
            # plan, after the timed runs so it cannot warm anything
            try:
                plan = "\n".join(r[0] for r in conn.execute("EXPLAIN (VERBOSE) " + sql))
            except psycopg.Error as e:
                plan = f"EXPLAIN failed: {e}"
            pd = classify_pushdown(path, plan)
            suffix = "" if args.resource_mode == "per-node" else f"_{args.resource_mode}"
            (out / "plans" / f"{path}_{dim}_{qid}{suffix}.txt").write_text(plan + "\n")
            w.writerow({"run_id": run_id, "ts": dt.datetime.now().isoformat(timespec="seconds"),
                        "path": path, "sf": args.sf, "dim_scenario": dim, "tier": tier,
                        "query_id": qid, "run_type": "explain", "iter": "", "latency_ms": "",
                        "status": "ok", "rows": "", "result_hash": "", "hash_match": "",
                        "pushdown": pd, "resource_mode": args.resource_mode,
                        "versions_json": "", "error": ""})
            fh.flush()
            conn.close()
        if path == "C" and args.resource_mode == "equal-total":
            set_cpus(C_PG_MAIN, engine_cpus)
            set_cpus(C_CH, engine_cpus)
    fh.close()


if __name__ == "__main__":
    main()
