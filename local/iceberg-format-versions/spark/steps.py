"""Run the same changes on Iceberg tables of format-version 1, 2 and 3 and record what each step wrote.

Run through run.sh (spark-submit inside the compose network). Output: results/spark-steps.txt.
Every step is recorded even when it fails: a refusal (for example merge-on-read on v1) is a result.
"""
import json
import os
import sys
import traceback

from pyspark.sql import SparkSession

NS = "lab.fv"
OUT = os.environ.get("OUT", "/lab/results/spark-steps.txt")
EXPECTED = os.environ.get("EXPECTED", "/lab/results/expected.json")
expected = {}  # what ClickHouse should return, as Spark sees it (clickhouse/read.py compares)

spark = (
    SparkSession.builder.appName("iceberg-format-versions")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.catalog.lab", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.lab.type", "rest")
    .config("spark.sql.catalog.lab.uri", "http://iceberg-rest:8181")
    .config("spark.sql.catalog.lab.warehouse", "s3://warehouse/")
    .config("spark.sql.catalog.lab.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
    .config("spark.sql.catalog.lab.s3.endpoint", "http://minio:9000")
    .config("spark.sql.catalog.lab.s3.path-style-access", "true")
    .config("spark.sql.session.timeZone", "UTC")
    .config("spark.sql.shuffle.partitions", "2")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("ERROR")

out = open(OUT, "w")


def say(line=""):
    print(line)
    out.write(line + "\n")
    out.flush()


def show(df, n=50):
    cols = df.columns
    rows = df.limit(n).collect()
    say("    | " + " | ".join(cols) + " |")
    for r in rows:
        say("    | " + " | ".join("" if v is None else str(v) for v in r) + " |")


def sql(stmt, quiet=False):
    if not quiet:
        say("  > " + " ".join(stmt.split()))
    return spark.sql(stmt)


def err(e):
    """The Java-side message (py4j wraps it in 'An error occurred while calling ...')."""
    je = getattr(e, "java_exception", None)
    text = je.toString() if je is not None else str(e)
    return " ".join(text.split())[:400]


def try_sql(stmt):
    try:
        sql(stmt)
        return True
    except Exception as e:  # recorded, not fatal
        say(f"    REFUSED: {err(e)}")
        return False


def state(t, lineage=False):
    """What the step left behind, from Iceberg's own metadata tables."""
    say("  snapshots:")
    show(sql(f"SELECT snapshot_id, operation, "
             f"map_filter(summary, (k, v) -> k RLIKE '^(added|deleted|removed)-.*(files|records|deletes|dvs)$' "
             f"AND v != '0') AS changes, summary['total-records'] AS total_records "
             f"FROM {t}.snapshots ORDER BY committed_at", quiet=True))
    files = sql(f"SELECT * FROM {t}.files", quiet=True)
    want = [c for c in ["content", "file_format", "spec_id", "record_count", "file_size_in_bytes",
                        "first_row_id", "referenced_data_file", "content_offset", "content_size_in_bytes",
                        "file_path"] if c in files.columns]
    files.createOrReplaceTempView("f")
    sel = ", ".join(
        "regexp_extract(file_path, '/(data/.*)$', 1) AS file_path" if c == "file_path" else
        "regexp_extract(referenced_data_file, '[^/]+$', 0) AS referenced_data_file" if c == "referenced_data_file" else c
        for c in want)
    say("  live files (content 0 = data, 1 = position deletes / deletion vectors, 2 = equality deletes):")
    show(sql(f"SELECT {sel} FROM f ORDER BY content, file_path", quiet=True))
    m = sql(f"SELECT file FROM {t}.metadata_log_entries ORDER BY timestamp DESC LIMIT 1", quiet=True).collect()
    if m:
        say("  current metadata file: " + m[0][0].split("/metadata/")[-1])
    if lineage:
        say("  row lineage (_row_id, _last_updated_sequence_number):")
        try:
            show(sql(f"SELECT id, _row_id, _last_updated_sequence_number FROM {t} ORDER BY id", quiet=True))
        except Exception as e:
            say("    REFUSED: " + err(e))


def record(t, lineage=False):
    name = t.split(".")[-1]
    e = expected.setdefault(name, {})
    r = sql(f"SELECT collect_list(id) AS ids FROM (SELECT id FROM {t} ORDER BY id)", quiet=True).collect()[0]
    e["ids"] = list(r["ids"])
    e["snapshot_id"] = sql(f"SELECT snapshot_id FROM {t}.snapshots ORDER BY committed_at DESC LIMIT 1",
                           quiet=True).collect()[0][0]
    if "amount_krw" in spark.table(t).columns:
        e["sum_amount"] = sql(f"SELECT sum(amount_krw) FROM {t}", quiet=True).collect()[0][0]
    if lineage:
        e["lineage"] = [list(x) for x in sql(f"SELECT id, _row_id, _last_updated_sequence_number FROM {t} ORDER BY id",
                                             quiet=True).collect()]


def rows(t):
    say("  table contents:")
    show(sql(f"SELECT * FROM {t} ORDER BY id", quiet=True))


def run_version(v):
    t = f"{NS}.t_v{v}"
    mode = "copy-on-write" if v == 1 else "merge-on-read"
    say(f"\n=== format-version {v}  ({t}, row-level mode {mode}) ===")

    say("\n-- step 1: create (partitioned by day of ts)")
    sql(f"DROP TABLE IF EXISTS {t} PURGE", quiet=True)
    sql(f"""CREATE TABLE {t} (id BIGINT, city STRING, amount DOUBLE, ts TIMESTAMP) USING iceberg
            PARTITIONED BY (days(ts))
            TBLPROPERTIES ('format-version'='{v}', 'write.delete.mode'='{mode}',
                           'write.update.mode'='{mode}', 'write.merge.mode'='{mode}')""")

    say("\n-- step 2: two inserts")
    sql(f"""INSERT INTO {t} VALUES (1,'Seoul',10.0,TIMESTAMP'2026-11-01 09:00:00'),
            (2,'Busan',20.0,TIMESTAMP'2026-11-01 10:00:00'), (3,'Incheon',30.0,TIMESTAMP'2026-11-01 11:00:00'),
            (4,'Daegu',40.0,TIMESTAMP'2026-11-02 09:00:00'), (5,'Gwangju',50.0,TIMESTAMP'2026-11-02 10:00:00')""")
    sql(f"""INSERT INTO {t} VALUES (6,'Seoul',60.0,TIMESTAMP'2026-11-02 11:00:00'),
            (7,'Busan',70.0,TIMESTAMP'2026-11-03 09:00:00'), (8,'Ulsan',80.0,TIMESTAMP'2026-11-03 10:00:00')""")
    state(t, lineage=(v == 3))
    expected.setdefault(t.split(".")[-1], {})["second_snapshot_id"] = sql(
        f"SELECT snapshot_id FROM {t}.snapshots ORDER BY committed_at DESC LIMIT 1", quiet=True).collect()[0][0]

    say("\n-- step 3: schema evolution (add a column, rename a column)")
    sql(f"ALTER TABLE {t} ADD COLUMN note STRING")
    sql(f"ALTER TABLE {t} RENAME COLUMN amount TO amount_krw")
    sql(f"INSERT INTO {t} VALUES (9,'Seoul',90.0,TIMESTAMP'2026-11-03 11:00:00','after add column')")
    rows(t)

    say("\n-- step 4: partition evolution (add bucket(4, id) to the spec)")
    sql(f"ALTER TABLE {t} ADD PARTITION FIELD bucket(4, id)")
    sql(f"INSERT INTO {t} VALUES (10,'Jeju',100.0,TIMESTAMP'2026-11-04 09:00:00','new spec')")
    state(t)

    say("\n-- step 5: delete rows (id 2 and 7)")
    if v == 1:
        say("  negative control: the same delete with merge-on-read requested on v1")
        sql(f"ALTER TABLE {t} SET TBLPROPERTIES ('write.delete.mode'='merge-on-read')")
        if try_sql(f"DELETE FROM {t} WHERE id IN (2, 7)"):
            say("    (accepted: see the files below for what it wrote)")
            state(t)
        sql(f"ALTER TABLE {t} SET TBLPROPERTIES ('write.delete.mode'='copy-on-write')")
    sql(f"DELETE FROM {t} WHERE id IN (2, 7)")
    state(t, lineage=(v == 3))

    say("\n-- step 6: update a row (id 3)")
    sql(f"UPDATE {t} SET amount_krw = amount_krw * 10, note = 'updated' WHERE id = 3")
    state(t, lineage=(v == 3))
    rows(t)
    record(t, lineage=(v == 3))

    if v == 3:
        say("\n-- step 7 (v3 only): types added in v3")
        try_sql(f"ALTER TABLE {t} ADD COLUMN payload VARIANT")
        try_sql(f"""INSERT INTO {t} SELECT 11,'Seoul',110.0,TIMESTAMP'2026-11-04 10:00:00','variant row',
                    parse_json('{{"device":"ios","tags":["a","b"],"score":7}}')""")
        rows(t)
        e = expected["t_v3"]
        e["before_variant"] = {k: e.pop(k) for k in ("ids", "snapshot_id", "sum_amount", "lineage")}
        record(t)
    else:
        say(f"\n-- negative control: a v3 type on a v{v} table")
        try_sql(f"ALTER TABLE {t} ADD COLUMN payload VARIANT")


def run_variant_at_create():
    """Control for step 7: the same variant data, but the column exists from CREATE (no schema evolution)."""
    t = f"{NS}.t_v3_variant"
    say(f"\n=== format-version 3, variant column from CREATE  ({t}) ===")
    sql(f"DROP TABLE IF EXISTS {t} PURGE", quiet=True)
    sql(f"CREATE TABLE {t} (id BIGINT, payload VARIANT) USING iceberg TBLPROPERTIES ('format-version'='3')")
    sql(f"""INSERT INTO {t} SELECT /*+ COALESCE(1) */ id, parse_json(j) FROM VALUES
            (1, '{{"device":"ios","tags":["a","b"],"score":7}}'), (2, '{{"device":"android","score":3}}'),
            (3, '42'), (4, '"text"'), (5, 'null') AS v(id, j)""")
    rows(t)
    record(t)


def run_upgrade():
    t = f"{NS}.t_v2_to_v3"
    say(f"\n=== upgrade: format-version 2 -> 3  ({t}) ===")
    sql(f"DROP TABLE IF EXISTS {t} PURGE", quiet=True)
    sql(f"""CREATE TABLE {t} (id BIGINT, city STRING) USING iceberg
            TBLPROPERTIES ('format-version'='2', 'write.delete.mode'='merge-on-read',
                           'write.update.mode'='merge-on-read', 'write.merge.mode'='merge-on-read')""")
    say("  (one data file: COALESCE(1), so the delete below needs a delete file instead of dropping a whole file)")
    sql(f"INSERT INTO {t} SELECT /*+ COALESCE(1) */ * FROM VALUES (1,'Seoul'),(2,'Busan'),(3,'Incheon'),(4,'Daegu'),(5,'Gwangju') AS v(id, city)")
    sql(f"DELETE FROM {t} WHERE id = 2")
    say("\n-- before the upgrade (v2: a position delete file)")
    state(t)
    say("\n-- upgrade")
    sql(f"ALTER TABLE {t} SET TBLPROPERTIES ('format-version'='3')")
    state(t, lineage=True)
    say("\n-- first write after the upgrade: insert, then delete id 4 (old file) and id 6 (new file)")
    sql(f"INSERT INTO {t} SELECT /*+ COALESCE(1) */ * FROM VALUES (6,'Ulsan'),(7,'Jeju') AS v(id, city)")
    sql(f"DELETE FROM {t} WHERE id IN (4, 6)")
    state(t, lineage=True)
    rows(t)
    record(t, lineage=True)
    say("\n-- downgrade attempt (negative control)")
    try_sql(f"ALTER TABLE {t} SET TBLPROPERTIES ('format-version'='2')")


try:
    say(f"Spark {spark.version}, Iceberg {os.environ.get('ICEBERG_VERSION', '?')}")
    sql("CREATE NAMESPACE IF NOT EXISTS lab.fv", quiet=True)
    for v in (1, 2, 3):
        run_version(v)
    run_variant_at_create()
    run_upgrade()
    with open(EXPECTED, "w") as f:
        json.dump(expected, f, indent=1)
    say("\nDONE")
except Exception:
    say("FAILED\n" + traceback.format_exc())
    sys.exit(1)
finally:
    out.close()
