"""Phase 0 gate: prove every integration before any number is trusted.

    python runner/verify.py 1

0-1  pg_lake created and wrote Iceberg tables in Polaris      (Polaris REST API)
0-2  all three engines read the same files from MinIO           (row counts per table)
0-3  ClickHouse DataLakeCatalog(rest) lists and reads the tables
0-4  pg_clickhouse pushes Q6's aggregate into Remote SQL
0-5  pg_duckdb (REST attach) returns the same Q6 result as pg_lake
0-6  pg_lake + pg_duckdb in one instance                         (not run: see docs)
Writes results/sf<N>/phase0.json.
"""
import json
import sys

import requests

from common import LAB, STATE, ch, classify_pushdown, connect, result_hash, set_active
from bench import SCHEMA, query_text

TABLES = ["lineitem_cold", "orders_cold", "customer", "part", "partsupp", "supplier",
          "nation", "region"]


def polaris_tables():
    r = STATE["reader"]
    tok = requests.post(STATE["oauth_uri"], data={
        "grant_type": "client_credentials", "client_id": r["client_id"],
        "client_secret": r["client_secret"], "scope": "PRINCIPAL_ROLE:ALL"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    base = f"{STATE['rest_uri']}/v1/{STATE['catalog']}"
    names = [t["name"] for t in requests.get(f"{base}/namespaces/tpch/tables", headers=h).json()["identifiers"]]
    snaps = {}
    for n in names:
        md = requests.get(f"{base}/namespaces/tpch/tables/{n}", headers=h).json()["metadata"]
        snaps[n] = {"snapshots": len(md.get("snapshots", [])),
                    "current_snapshot_id": md.get("current-snapshot-id"),
                    "format_version": md.get("format-version")}
    return sorted(names), snaps


def counts(path):
    out = {}
    with connect(path) as c:
        s = {"A": "tpch", "B": "b_d1", "B2": "b_d1", "C": "ch"}[path]
        for t in TABLES:
            name = t if path not in ("B", "B2") else t.replace("_cold", "")
            out[t] = c.execute(f"SELECT count(*) FROM {s}.{name}").fetchone()[0]
    return out


def q6(path):
    sql = query_text("q06")
    with connect(path) as c:
        c.execute(f"SET search_path = {SCHEMA[(path, 'D1')]}, public")
        h = result_hash(c.execute(sql).fetchall())
        plan = "\n".join(r[0] for r in c.execute("EXPLAIN (VERBOSE) " + sql))
    return h, classify_pushdown(path, plan), plan


def main(sf):
    rep = {"sf": sf}
    names, snaps = polaris_tables()
    rep["0-1"] = {"pass": set(TABLES) <= set(names), "polaris_tables": names, "metadata": snaps}

    set_active("C")
    a = counts("A")
    c_counts = counts("C")
    rep["0-3"] = {"pass": a == c_counts,
                  "clickhouse_tables": ch("SHOW TABLES FROM polaris").split(), "counts": c_counts}
    ha, pa, _ = q6("A")
    hc, pc, planc = q6("C")
    rep["0-4"] = {"pass": pc == "full" and hc == ha, "pushdown": pc, "hash_match": hc == ha,
                  "remote_sql": [l.strip() for l in planc.splitlines() if "Remote SQL" in l]}

    set_active("B")
    b = counts("B")
    hb, pb, planb = q6("B")
    rep["0-5"] = {"pass": hb == ha, "method": "REST ATTACH via login event trigger",
                  "pushdown": pb, "counts": b}
    set_active("B2")
    b2 = counts("B2")
    hb2, pb2, _ = q6("B2")
    rep["0-5b"] = {"pass": hb2 == ha, "method": "same, pg_duckdb main build (reference B')",
                   "pushdown": pb2, "counts": b2}
    rep["0-2"] = {"pass": a == b == b2 == c_counts, "pg_lake_counts": a}
    rep["0-6"] = {"pass": None, "note": "not run; pg_lake's DuckDB runs in the separate "
                  "pgduck_server process, so the open question is hook ordering, not two "
                  "libduckdb copies in one backend. See docs/DESIGN.md."}
    rep["q6_pushdown_A"] = pa
    (LAB / "results" / f"sf{sf}").mkdir(parents=True, exist_ok=True)
    (LAB / "results" / f"sf{sf}" / "phase0.json").write_text(json.dumps(rep, indent=2, default=str))
    for k in ("0-1", "0-2", "0-3", "0-4", "0-5", "0-5b", "0-6"):
        print(k, {True: "PASS", False: "FAIL", None: "SKIP"}[rep[k]["pass"]])
    print(json.dumps({k: v for k, v in rep.items() if k in ("0-2", "0-4")}, indent=1, default=str))


if __name__ == "__main__":
    main(int(sys.argv[1]))
