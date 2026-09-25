"""§5.4 direct-execution baseline: the same query without Postgres in front.

    python runner/direct.py 10

  A-direct  pgduck_server over its Unix socket, tables as iceberg_scan(<metadata.json>)
  C-direct  ClickHouse over HTTP, tables as bench.* (same Polaris-backed views)
compared with the warm p50 of paths A and C going through Postgres.
Q6 (L1) and Q3 (L3) only. Writes results/sf<N>/direct.csv.
"""
import csv
import re
import statistics
import sys
import time

import requests

from common import C_PG_MAIN, LAB, connect, container, polaris_metadata_location, set_active
from bench import SCHEMA, query_text

QUERIES = {"q06": ["lineitem"], "q03": ["customer", "orders", "lineitem"]}
N = 5


def median_ms(fn):
    fn()  # warm-up
    ts = []
    for _ in range(N):
        t0 = time.perf_counter()
        fn()
        ts.append((time.perf_counter() - t0) * 1000)
    return round(statistics.median(ts), 1)


def pgduck_direct(sql):
    out = container(C_PG_MAIN).exec_run(
        ["psql", "-X", "-h", "/var/lib/pgduck/socket", "-p", "5332", "-At",
         "-c", "\\timing on", "-c", sql]).output.decode()
    m = re.findall(r"Time: ([\d.]+) ms", out)
    if not m:
        raise RuntimeError(out[:500])
    return float(m[-1])


def main(sf):
    rows = []
    set_active("C")
    md = {t: polaris_metadata_location(t) for t in
          ("lineitem_cold", "orders_cold", "customer")}
    for qid, tables in QUERIES.items():
        sql = query_text(qid).rstrip().rstrip(";")
        body = "\n".join(l for l in sql.splitlines() if not l.startswith("--"))
        # through Postgres
        for path in ("A", "C"):
            with connect(path) as c:
                c.execute(f"SET search_path = {SCHEMA[(path, 'D1')]}, public")
                ms = median_ms(lambda: c.execute(body).fetchall())
            rows.append({"sf": sf, "query_id": qid, "route": f"{path} via Postgres", "warm_p50_ms": ms})
        # pgduck_server directly: server-side time reported by psql \timing
        cte = ", ".join(f"{t} AS (SELECT * FROM iceberg_scan('{md[t + '_cold' if t in ('lineitem', 'orders') else t]}'))"
                        for t in tables)
        dsql = f"WITH {cte} {body}"
        pgduck_direct(dsql)
        rows.append({"sf": sf, "query_id": qid, "route": "A-direct pgduck_server",
                     "warm_p50_ms": round(statistics.median(pgduck_direct(dsql) for _ in range(N)), 1)})
        # ClickHouse directly over HTTP
        csql = re.sub(r"date '(\d{4}-\d{2}-\d{2})'", r"toDate('\1')", body)
        for t in tables:
            csql = re.sub(rf"\b{t}\b(?!_)", f"bench.{t}_cold" if t in ("lineitem", "orders") else f"bench.{t}", csql)

        def run_ch():
            r = requests.post("http://clickhouse:8123/", data=csql.encode(), timeout=600)
            r.raise_for_status()
        rows.append({"sf": sf, "query_id": qid, "route": "C-direct clickhouse", "warm_p50_ms": median_ms(run_ch)})
        for r in rows[-4:]:
            print(r, flush=True)
    with open(LAB / "results" / f"sf{sf}" / "direct.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main(int(sys.argv[1]))
