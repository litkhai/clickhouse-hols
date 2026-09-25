"""Build one scale factor end to end (Phase 1) and wire up the readers.

    python runner/setup.py load    10   # heap load -> Iceberg tables -> tiering -> VACUUM
    python runner/setup.py readers 10   # ClickHouse catalog, pg_clickhouse FDW, pg_duckdb copy
    python runner/setup.py all     10

Writes results/sf<N>/tiering.csv and results/sf<N>/layout.csv.
Only one scale factor is materialised at a time: `load` drops the previous one.
"""
import csv
import os
import subprocess
import sys
import time

from common import (C_CH, C_PG_DUCK, C_PG_DUCK_MAIN, C_PG_MAIN, DB, LAB, PG_HOST, STATE, ch,
                    connect, container, psql, wait_ready)

HOT_CUTOFF = os.environ.get("HOT_CUTOFF", "1998-02-01")
BUCKET = os.environ.get("S3_BUCKET", "warehouse")
DIMS = ["customer", "part", "partsupp", "supplier", "nation", "region"]


def out_dir(sf):
    d = LAB / "results" / f"sf{sf}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def ensure_db(name):
    exists = psql(name, f"SELECT 1 FROM pg_database WHERE datname = '{DB}'", db="postgres")
    if " 1\n" not in exists:
        psql(name, f"CREATE DATABASE {DB}", db="postgres")


# ------------------------------------------------------------------ Phase 1
def load(sf, bulk=False):
    for n in (C_PG_MAIN,):
        if container(n).status != "running":
            container(n).start()
        wait_ready(n)
    ensure_db(C_PG_MAIN)
    init = LAB / "init" / "pg-main"
    print(psql(C_PG_MAIN, file=init / "01-extensions.sql", variables={
        "rest_host": STATE["rest_uri"],
        "writer_id": STATE["writer"]["client_id"],
        "writer_secret": STATE["writer"]["client_secret"]}))
    psql(C_PG_MAIN, f"ALTER DATABASE {DB} SET ilm.hot_cutoff = '{HOT_CUTOFF}'")
    psql(C_PG_MAIN, f"ALTER DATABASE {DB} SET bench.staging = 's3://{BUCKET}/staging/sf{sf}/'")

    t0 = time.time()
    v = {"bulk": "on" if bulk else "off"}
    print(psql(C_PG_MAIN, file=init / "02-heap-load.sql", variables=v))
    heap_s = time.time() - t0
    print(f"heap load sf{sf}: {heap_s:.0f}s")

    t0 = time.time()
    print(psql(C_PG_MAIN, file=init / "03-iceberg-tables.sql", variables=v))
    psql(C_PG_MAIN, file=LAB / "ilm" / "tiering.sql")
    if bulk:
        cold_s = time.time() - t0
        print(f"bulk cold write sf{sf}: {cold_s:.0f}s")
        with open(out_dir(sf) / "load.csv", "w") as f:
            f.write("sf,mode,heap_load_s,cold_write_s\n%s,bulk,%.1f,%.1f\n" % (sf, heap_s, cold_s))
    else:
        tier(sf, heap_s)
    vacuum_and_layout(sf)


def tier(sf, heap_s):
    """Run the monthly tiering job over every month older than HOT_CUTOFF."""
    rows = []
    with connect("A") as c:
        for table in ("orders", "lineitem"):
            months = [r[0] for r in c.execute("SELECT ilm.pending_months(%s)", (table,))]
            for m in months:
                t0 = time.perf_counter()
                n = c.execute("SELECT ilm.tier_month(%s, %s)", (table, m)).fetchone()[0]
                dt = time.perf_counter() - t0
                rows.append({"sf": sf, "table": table, "month": m.isoformat(), "rows": n,
                             "seconds": round(dt, 3), "rows_per_s": round(n / dt) if dt else 0})
            print(f"tiered {table}: {len(months)} months, "
                  f"{sum(r['rows'] for r in rows if r['table'] == table):,} rows, "
                  f"{sum(r['seconds'] for r in rows if r['table'] == table):.0f}s")
    with open(out_dir(sf) / "tiering.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with open(out_dir(sf) / "load.csv", "w") as f:
        f.write("sf,heap_load_s\n%s,%.1f\n" % (sf, heap_s))


# pg_lake keeps its own file inventory; for catalog = 'rest' tables the
# metadata.json location lives only in Polaris, so iceberg_tables shows none.
LAYOUT_SQL = """
SELECT table_name::text, CASE content WHEN 0 THEN 'data' ELSE 'delete' END AS content,
       count(*) AS files, sum(row_count) AS records,
       round(avg(file_size) / 1048576.0, 2) AS avg_file_mb,
       round(sum(file_size) / 1048576.0, 1) AS total_mb
FROM lake_table.files
WHERE table_name::text LIKE 'tpch.%'
GROUP BY 1, 2 ORDER BY 1, 2
"""


def vacuum_and_layout(sf):
    with connect("A") as c:
        before = c.execute(LAYOUT_SQL).fetchall()
        t0 = time.time()
        c.execute("VACUUM (ICEBERG)")
        vac_s = time.time() - t0
        after = c.execute(LAYOUT_SQL).fetchall()
    with open(out_dir(sf) / "layout.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["stage", "table", "content", "files", "records", "avg_file_mb", "total_mb"])
        for stage, rs in (("after_tiering", before), ("after_vacuum", after)):
            for r in rs:
                w.writerow([stage, *r])
        w.writerow(["vacuum_seconds", round(vac_s, 1), "", "", "", "", ""])
    print(f"VACUUM (ICEBERG): {vac_s:.0f}s")
    for r in after:
        print("  ", r)


# ------------------------------------------------------------------ readers
def readers(sf):
    for n in (C_PG_MAIN, C_CH, C_PG_DUCK, C_PG_DUCK_MAIN):
        if container(n).status != "running":
            container(n).start()
        wait_ready(n)
    # ---- path C: ClickHouse sees Polaris as a database, pg-main imports it
    r = STATE["reader"]
    ddl = (LAB / "init" / "clickhouse" / "sql" / "01-catalog.sql").read_text()
    ddl = (ddl.replace("{reader_credential}", f"{r['client_id']}:{r['client_secret']}")
              .replace("{s3_key}", os.environ["S3_ACCESS_KEY"])
              .replace("{s3_secret}", os.environ["S3_SECRET_KEY"]))
    for stmt in split_sql(ddl):
        ch(stmt)
    print(ch("SELECT name, engine FROM system.tables WHERE database = 'bench' ORDER BY 1"))
    print(psql(C_PG_MAIN, file=LAB / "init" / "pg-main" / "04-clickhouse-fdw.sql"))
    psql(C_PG_MAIN, file=LAB / "init" / "pg-main" / "05-views.sql")

    # ---- paths B / B': static copy of the hot tier + heap dimensions, then the lake views
    for duck in (C_PG_DUCK, C_PG_DUCK_MAIN):
        ensure_db(duck)
        psql(duck, "DROP SCHEMA IF EXISTS hot CASCADE")
        dump = subprocess.run(
            f"set -o pipefail; pg_dump -h pg-main -U postgres -d {DB} -n hot --no-owner | "
            f"psql -X -q -v ON_ERROR_STOP=1 -h {PG_HOST[duck]} -U postgres -d {DB}",
            shell=True, capture_output=True, text=True, executable="/bin/bash")
        if dump.returncode != 0:
            raise RuntimeError(dump.stderr)
        psql(duck, "ANALYZE")
        setup_pg_duck(duck)


def split_sql(text):
    body = "\n".join(l for l in text.splitlines() if not l.strip().startswith("--"))
    return [s.strip() for s in body.split(";") if s.strip()]


PG_DUCK_ATTACH = """
CREATE EXTENSION IF NOT EXISTS pg_duckdb;
SELECT duckdb.install_extension('iceberg');

-- DuckDB's ATTACH lives in the backend's DuckDB instance, so it is gone on
-- the next connection (risk R4). A PG18 login event trigger re-attaches
-- Polaris for every session, which makes the lake views below usable from
-- any client without it knowing about DuckDB.
-- No EXCEPTION block: it would open a subtransaction, which DuckDB refuses.
-- If the attach fails, logins to pg-duck fail; recover with
--   PGOPTIONS='-c event_triggers=off' psql ...
CREATE OR REPLACE FUNCTION public.bench_attach_polaris() RETURNS event_trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM duckdb.raw_query($q$CREATE SECRET IF NOT EXISTS minio (TYPE s3,
      KEY_ID '{s3_key}', SECRET '{s3_secret}', ENDPOINT 'minio:9000',
      URL_STYLE 'path', USE_SSL false, REGION 'us-east-1')$q$);
  PERFORM duckdb.raw_query($q$CREATE SECRET IF NOT EXISTS polaris_s (TYPE iceberg,
      CLIENT_ID '{rid}', CLIENT_SECRET '{rsecret}',
      OAUTH2_SERVER_URI 'http://polaris:8181/api/catalog/v1/oauth/tokens',
      OAUTH2_SCOPE 'PRINCIPAL_ROLE:ALL')$q$);
  PERFORM duckdb.raw_query($q$ATTACH IF NOT EXISTS 'ilm' AS polaris (TYPE iceberg,
      SECRET polaris_s, ENDPOINT 'http://polaris:8181/api/catalog',
      ACCESS_DELEGATION_MODE 'none')$q$);
END $fn$;
DROP EVENT TRIGGER IF EXISTS bench_attach_polaris;
CREATE EVENT TRIGGER bench_attach_polaris ON login EXECUTE FUNCTION public.bench_attach_polaris();
"""


def setup_pg_duck(duck):
    r = STATE["reader"]
    sql = (PG_DUCK_ATTACH.replace("{s3_key}", os.environ["S3_ACCESS_KEY"])
           .replace("{s3_secret}", os.environ["S3_SECRET_KEY"])
           .replace("{rid}", r["client_id"]).replace("{rsecret}", r["client_secret"]))
    tmp = LAB / ".state" / "pg-duck-attach.sql"
    tmp.write_text(sql)
    psql(duck, file=tmp)
    tmp.unlink()

    # column lists come from the heap schema so the typed views match path A exactly
    with connect("A") as c:
        cols = {}
        for t, col, typ in c.execute(
                "SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod) "
                "FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid "
                "JOIN pg_namespace n ON n.oid = c.relnamespace "
                "WHERE n.nspname = 'hot' AND c.relkind = 'r' AND a.attnum > 0 "
                "AND NOT a.attisdropped ORDER BY c.relname, a.attnum"):
            cols.setdefault(t, []).append((col, typ))

    def lake_view(schema, name, lake_table):
        sel = ", ".join(f"r['{c}']::{t} AS {c}" for c, t in cols[name])
        return (f"CREATE VIEW {schema}.{name} AS SELECT {sel} FROM "
                f"duckdb.query($q$SELECT * FROM polaris.tpch.{lake_table}$q$) r;")

    stmts = []
    for s in ("b_d1", "b_d2"):
        stmts += [f"DROP SCHEMA IF EXISTS {s} CASCADE;", f"CREATE SCHEMA {s};"]
        stmts.append(lake_view(s, "lineitem", "lineitem_cold").replace(
            f"VIEW {s}.lineitem ", f"VIEW {s}.lineitem "))
        stmts.append(lake_view(s, "orders", "orders_cold"))
        stmts.append(f"CREATE VIEW {s}.lineitem_all AS SELECT * FROM hot.lineitem "
                     f"UNION ALL SELECT * FROM {s}.lineitem;")
        stmts.append(f"CREATE VIEW {s}.orders_all AS SELECT * FROM hot.orders "
                     f"UNION ALL SELECT * FROM {s}.orders;")
        for d in DIMS:
            if s == "b_d1":
                stmts.append(lake_view(s, d, d))
            else:
                stmts.append(f"CREATE VIEW {s}.{d} AS SELECT * FROM hot.{d};")
    tmp = LAB / ".state" / "pg-duck-views.sql"
    tmp.write_text("\n".join(stmts))
    psql(duck, file=tmp)
    tmp.unlink()


if __name__ == "__main__":
    what, sf = sys.argv[1], int(sys.argv[2])
    if what in ("load", "all"):
        load(sf, bulk="--bulk" in sys.argv[3:])
    if what in ("readers", "all"):
        readers(sf)
