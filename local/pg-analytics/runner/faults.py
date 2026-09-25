"""Phase 1 fault injection: is heap -> Iceberg tiering atomic with an external catalog?

    python runner/faults.py 10

Works on its own pair of tables (hot.fault_orders -> tpch.fault_orders_cold,
one year of orders), so the benchmark snapshot is never touched.

For each trial one month is being tiered when the fault hits:
  kill    docker kill pg-main (SIGKILL) at a chosen point of the transaction
  polaris docker stop polaris while the transaction runs
Right after recovery the month is classified by where its rows are:
  rolled_back  all in heap, none in lake     (transaction never happened)
  committed    none in heap, all in lake     (transaction fully happened)
  duplicate    all in heap AND all in lake   (lake commit survived, PG commit did not)
  lost / partial / diverged                  (anything else; diverged = pg_lake and
                                              ClickHouse-through-Polaris disagree)
Then ilm.tier_month is simply re-run, and the month must end up exactly once.
Writes results/sf<N>/faults.csv.
"""
import csv
import sys
import threading
import time

import psycopg

from common import (C_CH, C_PG_MAIN, LAB, ch, connect, container, set_active, wait_ready)

YEAR_LO, YEAR_HI = "1995-01-01", "1996-01-01"


def pg(sql, params=None):
    with connect("A") as c:
        return c.execute(sql, params).fetchall()


def setup():
    with connect("A") as c:
        c.execute("DROP TABLE IF EXISTS tpch.fault_orders_cold")
        c.execute("DROP TABLE IF EXISTS hot.fault_orders")
        c.execute(f"CREATE TABLE hot.fault_orders AS SELECT * FROM staging.orders "
                  f"WHERE o_orderdate >= '{YEAR_LO}' AND o_orderdate < '{YEAR_HI}'")
        c.execute("CREATE INDEX ON hot.fault_orders (o_orderdate)")
        c.execute("CREATE TABLE tpch.fault_orders_cold (LIKE hot.fault_orders) USING iceberg "
                  "WITH (catalog = 'rest', partition_by = 'month(o_orderdate)', "
                  "autovacuum_enabled = 'false')")
        return c.execute("SELECT count(*), sum(o_orderkey), sum(o_totalprice) "
                         "FROM hot.fault_orders").fetchone()


def month_state(m):
    lo, hi = m, f"({m!r}::date + interval '1 month')::date"
    cond = f"o_orderdate >= '{m}' AND o_orderdate < {hi}"
    heap = pg(f"SELECT count(*) FROM hot.fault_orders WHERE {cond}")[0][0]
    lake = pg(f"SELECT count(*) FROM tpch.fault_orders_cold WHERE {cond}")[0][0]
    via_ch = int(ch(f"SELECT count() FROM polaris.`tpch.fault_orders_cold` WHERE "
                    f"o_orderdate >= '{m}' AND o_orderdate < toDate('{m}') + INTERVAL 1 MONTH").strip())
    return heap, lake, via_ch


def classify(n, heap, lake, via_ch):
    if lake != via_ch:
        return "diverged"
    if heap == n and lake == 0:
        return "rolled_back"
    if heap == 0 and lake == n:
        return "committed"
    if heap == n and lake == n:
        return "duplicate"
    if heap == 0 and lake == 0:
        return "lost"
    return "partial"


def tier_async(m, box):
    def go():
        t0 = time.perf_counter()
        try:
            with connect("A") as c:
                box["rows"] = c.execute("SELECT ilm.tier_month('fault_orders', %s)", (m,)).fetchone()[0]
            box["result"] = "returned"
        except psycopg.Error as e:
            box["result"] = "error: " + str(e).splitlines()[0][:160]
        box["seconds"] = time.perf_counter() - t0
    t = threading.Thread(target=go, daemon=True)
    t.start()
    return t


def main(sf):
    set_active("C")  # pg-main + clickhouse: the second opinion comes through Polaris
    expected = setup()
    months = [r[0].isoformat() for r in pg("SELECT ilm.pending_months('fault_orders')")]
    per_month = {m: pg("SELECT count(*) FROM hot.fault_orders WHERE date_trunc('month', o_orderdate) = %s",
                       (m,))[0][0] for m in months}

    # calibrate: time one clean month end to end
    box = {}
    tier_async(months[0], box).join()
    T = box["seconds"]
    print(f"clean tier_month: {T:.2f}s for {box['rows']} rows")
    rows = [{"trial": 0, "fault": "none", "month": months[0], "fault_at_s": "",
             "tx_result": box["result"], "after_fault": "committed", "heap": 0,
             "lake_pg_lake": per_month[months[0]], "lake_clickhouse": per_month[months[0]],
             "after_rerun": "committed", "clean_tier_s": round(T, 2)}]

    plan = [("kill", f) for f in (0.1, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 1.0, 1.05)] + \
           [("polaris", 0.2), ("polaris", 0.6)]
    for i, ((fault, frac), m) in enumerate(zip(plan, months[1:]), start=1):
        n = per_month[m]
        box = {}
        t = tier_async(m, box)
        time.sleep(T * frac)
        if fault == "kill":
            container(C_PG_MAIN).kill()
            t.join(timeout=30)
            container(C_PG_MAIN).start()
        else:
            container("pga-polaris").stop(timeout=5)
            t.join(timeout=300)
            container("pga-polaris").start()
            wait_ready_polaris()
        wait_ready(C_PG_MAIN)
        heap, lake, via_ch = month_state(m)
        state = classify(n, heap, lake, via_ch)
        # recovery is just the same job again
        with connect("A") as c:
            c.execute("SELECT ilm.tier_month('fault_orders', %s)", (m,))
        h2, l2, c2 = month_state(m)
        after = classify(n, h2, l2, c2)
        r = {"trial": i, "fault": fault, "month": m, "fault_at_s": round(T * frac, 2),
             "tx_result": box.get("result", "killed"), "after_fault": state, "heap": heap,
             "lake_pg_lake": lake, "lake_clickhouse": via_ch, "after_rerun": after,
             "clean_tier_s": round(T, 2)}
        print(r, flush=True)
        rows.append(r)

    # finish the year, then the whole year must add up exactly
    with connect("A") as c:
        for m in months:
            c.execute("SELECT ilm.tier_month('fault_orders', %s)", (m,))
        got = c.execute("SELECT count(*), sum(o_orderkey), sum(o_totalprice) FROM ("
                        "SELECT * FROM hot.fault_orders UNION ALL "
                        "SELECT * FROM tpch.fault_orders_cold) u").fetchone()
    ok = tuple(got) == tuple(expected)
    print(f"year total expected={expected} got={got} -> {'EXACT' if ok else 'MISMATCH'}")
    rows.append({"trial": "total", "fault": "", "month": "1995", "fault_at_s": "",
                 "tx_result": f"expected={tuple(expected)} got={tuple(got)}",
                 "after_fault": "", "heap": "", "lake_pg_lake": "", "lake_clickhouse": "",
                 "after_rerun": "exact" if ok else "MISMATCH", "clean_tier_s": ""})
    with open(LAB / "results" / f"sf{sf}" / "faults.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with connect("A") as c:
        c.execute("DROP TABLE tpch.fault_orders_cold")
        c.execute("DROP TABLE hot.fault_orders")


def wait_ready_polaris(timeout=120):
    import requests
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            if requests.get("http://polaris:8181/api/catalog/v1/config", timeout=2).status_code in (200, 401, 400):
                return
        except Exception:
            pass
        time.sleep(1)


if __name__ == "__main__":
    main(int(sys.argv[1]))
