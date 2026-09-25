"""Phase 4: ILM operations seen from the three read paths.

    python runner/ilm_ops.py deletes   10   # erasure: 0.1% / 1% / 5% of cold lineitem, then VACUUM
    python runner/ilm_ops.py freshness 10   # commit -> visible-to-reader lag for B and C
    python runner/ilm_ops.py expiry    10   # snapshot expiry vs a reader pinned to old metadata

Run last: it changes the benchmark snapshot. Writes results/sf<N>/ilm_*.csv.
"""
import csv
import statistics
import sys
import time

import psycopg

from common import LAB, ch, connect, container, polaris_metadata_location, set_active
from bench import SCHEMA, query_text

LAYOUT = """SELECT CASE content WHEN 0 THEN 'DATA' ELSE 'DELETES' END, count(*),
                   sum(CASE content WHEN 0 THEN deleted_row_count ELSE row_count END)
            FROM lake_table.files WHERE table_name = 'tpch.lineitem_cold'::regclass
            GROUP BY 1 ORDER BY 1"""


def write(sf, name, rows):
    with open(LAB / "results" / f"sf{sf}" / f"ilm_{name}.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def warm_median(path, qid, n=3):
    sql = query_text(qid)
    with connect(path) as c:
        c.execute(f"SET search_path = {SCHEMA[(path, 'D1')]}, public")
        c.execute("SET statement_timeout = '300s'")
        c.execute(sql).fetchall()
        ts = []
        for _ in range(n):
            t0 = time.perf_counter()
            c.execute(sql).fetchall()
            ts.append((time.perf_counter() - t0) * 1000)
        cnt = c.execute("SELECT count(*) FROM lineitem").fetchone()[0]
    return round(statistics.median(ts), 1), cnt


# ------------------------------------------------------------------ deletes
STEPS = [("0.1%", "l_orderkey % 1000 = 1"),
         ("1%", "l_orderkey % 1000 BETWEEN 2 AND 10"),
         ("5%", "l_orderkey % 1000 BETWEEN 11 AND 50")]


def measure(sf, stage, rows):
    with connect("A") as c:
        layout = {r[0]: (r[1], r[2]) for r in c.execute(LAYOUT)}
    for path in ("A", "B", "B2", "C"):
        set_active(path)
        for qid in ("q01", "q06", "q03"):
            ms, cnt = warm_median(path, qid)
            rows.append({"stage": stage, "path": path, "query_id": qid, "warm_p50_ms": ms,
                         "lineitem_rows_seen": cnt,
                         "data_files": layout.get("DATA", ("", ""))[0],
                         "delete_files": sum(v[0] for k, v in layout.items() if k != "DATA"),
                         "deleted_positions": sum(v[1] for k, v in layout.items() if k != "DATA")})
            print(rows[-1], flush=True)


def deletes(sf):
    set_active("A")
    rows = []
    measure(sf, "baseline", rows)
    for label, cond in STEPS:
        set_active("A")
        with connect("A") as c:
            t0 = time.perf_counter()
            n = c.execute(f"DELETE FROM tpch.lineitem_cold WHERE {cond}").rowcount
            print(f"deleted {n:,} rows ({label} step) in {time.perf_counter() - t0:.1f}s")
        measure(sf, f"after_delete_{label}", rows)
    set_active("A")
    with connect("A") as c:
        t0 = time.perf_counter()
        c.execute("VACUUM (ICEBERG)")
        print(f"VACUUM {time.perf_counter() - t0:.1f}s")
    measure(sf, "after_vacuum", rows)
    write(sf, "deletes", rows)


# ------------------------------------------------------------------ freshness
def freshness(sf, trials=5):
    for n in ("pga-pg-main", "pga-pg-duck", "pga-clickhouse"):
        if container(n).status != "running":
            container(n).start()
    set_active("A")
    for n in ("pga-pg-duck", "pga-clickhouse"):
        container(n).start()
    time.sleep(10)
    rows = []
    b_sticky = connect("B")  # one long-lived reader session, like a pooled connection
    for t in range(trials):
        marker = f"fresh-{int(time.time())}-{t}"
        with connect("A") as a:
            a.execute("INSERT INTO tpch.orders_cold SELECT o_orderkey + 900000000 + %s * 1000, "
                      "o_custkey, o_orderstatus, o_totalprice, o_orderdate, o_orderpriority, "
                      "o_clerk, o_shippriority, %s FROM tpch.orders_cold "
                      "WHERE o_orderdate = date '1992-01-01' LIMIT 1000", (t, marker))
        committed = time.perf_counter()
        seen = {}
        deadline = committed + 120
        while len(seen) < 3 and time.perf_counter() < deadline:
            if "C" not in seen:
                n = int(ch(f"SELECT count() FROM polaris.`tpch.orders_cold` WHERE o_comment = '{marker}'"))
                if n == 1000:
                    seen["C"] = time.perf_counter() - committed
            if "B_new_session" not in seen:
                with connect("B") as b:
                    n = b.execute("SELECT count(*) FROM b_d1.orders WHERE o_comment = %s",
                                  (marker,)).fetchone()[0]
                if n == 1000:
                    seen["B_new_session"] = time.perf_counter() - committed
            if "B_same_session" not in seen:
                n = b_sticky.execute("SELECT count(*) FROM b_d1.orders WHERE o_comment = %s",
                                     (marker,)).fetchone()[0]
                if n == 1000:
                    seen["B_same_session"] = time.perf_counter() - committed
            time.sleep(0.1)
        for reader in ("C", "B_new_session", "B_same_session"):
            rows.append({"trial": t, "reader": reader,
                         "visible_after_ms": round(seen[reader] * 1000) if reader in seen else "not within 120s"})
            print(rows[-1], flush=True)
    with connect("A") as a:
        a.execute("DELETE FROM tpch.orders_cold WHERE o_comment LIKE 'fresh-%'")
    write(sf, "freshness", rows)


# ------------------------------------------------------------------ expiry
def expiry(sf):
    set_active("B")
    container("pga-pg-main").start()
    time.sleep(10)
    rows = []
    with connect("A") as a:
        old_md = polaris_metadata_location("region")
        snaps_before = a.execute("SELECT count(*) FROM lake_iceberg.snapshots(%s)", (old_md,)).fetchone()[0]
        a.execute("UPDATE tpch.region SET r_comment = r_comment || ' (edited)'")
        a.execute("ALTER FOREIGN TABLE tpch.region OPTIONS (ADD max_snapshot_age '0')")
        a.execute("VACUUM (ICEBERG)")
        new_md = polaris_metadata_location("region")
        snaps_after = a.execute("SELECT count(*) FROM lake_iceberg.snapshots(%s)", (new_md,)).fetchone()[0]
    rows.append({"check": "snapshots in current metadata", "before": snaps_before, "after": snaps_after})

    def read(md):
        try:
            with connect("B") as b:
                n = b.execute(f"SELECT count(*) FROM duckdb.query($q$SELECT * FROM iceberg_scan('{md}')$q$)").fetchone()[0]
            return f"ok ({n} rows)"
        except psycopg.Error as e:
            return "error: " + str(e).splitlines()[0][:200]

    rows.append({"check": "B iceberg_scan(old metadata.json) after expiry", "before": "", "after": read(old_md)})
    with connect("B") as b:
        n = b.execute("SELECT count(*) FROM b_d1.region WHERE r_comment LIKE '%(edited)'").fetchone()[0]
    rows.append({"check": "B via Polaris sees the edit", "before": "", "after": f"{n} of 5 rows"})
    container("pga-clickhouse").start()
    time.sleep(8)
    n = ch("SELECT count() FROM polaris.`tpch.region` WHERE r_comment LIKE '%(edited)'").strip()
    rows.append({"check": "C via Polaris sees the edit", "before": "", "after": f"{n} of 5 rows"})
    for r in rows:
        print(r)
    write(sf, "expiry", rows)


if __name__ == "__main__":
    {"deletes": deletes, "freshness": freshness, "expiry": expiry}[sys.argv[1]](int(sys.argv[2]))
