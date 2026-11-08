"""Read the lab's Iceberg tables from ClickHouse and compare with what Spark returned.

Runs on the host (standard library only) and sends each query to the compose `clickhouse` service.
Input: results/expected.json (written by spark/steps.py). Output: results/clickhouse-<version>.txt.
A check is MATCH, DIFF (ClickHouse answered, differently) or ERROR (ClickHouse raised).
"""
import json
import os
import subprocess
import sys

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXP = json.load(open(os.path.join(LAB, "results", "expected.json")))
CRED = "'admin', 'password123'"
lines, counts = [], {"MATCH": 0, "DIFF": 0, "ERROR": 0}


def ch(query):
    # allow_database_iceberg: DataLakeCatalog with a REST catalog is beta in 26.10 (SUPPORT_IS_DISABLED without it)
    r = subprocess.run(["docker", "compose", "exec", "-T", "clickhouse", "clickhouse-client",
                        "--allow_database_iceberg=1", "--format", "JSONCompactEachRow", "-q", query],
                       cwd=LAB, capture_output=True, text=True)
    if r.returncode != 0:
        msg = " ".join(r.stderr.split())
        raise RuntimeError(msg[msg.find("DB::Exception"):][:400] if "DB::Exception" in msg else msg[:400])
    return [json.loads(x) for x in r.stdout.splitlines() if x.strip()]


def say(s=""):
    print(s)
    lines.append(s)


def check(label, query, expected, shape=lambda rows: rows):
    say(f"- {label}")
    say(f"    query:    {' '.join(query.split())}")
    try:
        got = shape(ch(query))
    except RuntimeError as e:
        counts["ERROR"] += 1
        say(f"    ERROR     {e}")
        return
    verdict = "MATCH" if got == expected else "DIFF"
    counts[verdict] += 1
    say(f"    spark:    {expected}")
    say(f"    {verdict.lower():9} {got}")


def src(t):
    return f"icebergS3('http://minio:9000/warehouse/fv/{t}/', {CRED})"


ids_sum = lambda rows: [rows[0][0], float(rows[0][1])] if rows else rows  # noqa: E731
ids = lambda rows: rows[0][0] if rows else rows  # noqa: E731

version = ch("SELECT version()")[0][0]
say(f"# ClickHouse {version} reading the lab tables (spark/steps.py wrote them)\n")

say("## v1 and v2: rows after delete and update")
for t in ("t_v1", "t_v2"):
    e = EXP[t]
    check(f"{t}: ids and sum(amount_krw)",
          f"SELECT groupArray(id), sum(amount_krw) FROM (SELECT id, amount_krw FROM {src(t)} ORDER BY id)",
          [e["ids"], float(e["sum_amount"])], ids_sum)

say("\n## v1 and v2: time travel to the second insert (8 rows, nothing deleted yet)")
for t in ("t_v1", "t_v2"):
    check(f"{t}: count() at the 2nd snapshot (iceberg_snapshot_id)",
          f"SELECT count() FROM {src(t)} SETTINGS iceberg_snapshot_id = {EXP[t]['second_snapshot_id']}"
          if "second_snapshot_id" in EXP[t] else "SELECT 'no snapshot id recorded'", [[8]])

say("\n## deleted rows are still in the data files (merge-on-read)")
for t, live in (("t_v2", len(EXP["t_v2"]["ids"])), ("t_v3", len(EXP["t_v3"]["ids"]))):
    check(f"{t}: rows in the Parquet data files (delete files excluded) vs rows in the table ({live})",
          f"SELECT count() FROM s3('http://minio:9000/warehouse/fv/{t}/data/**/*.parquet', {CRED}, 'Parquet', 'id Int64') "
          f"WHERE _file NOT LIKE '%-deletes.parquet'",
          "data files hold more rows than the table", lambda r: "data files hold more rows than the table"
          if r and r[0][0] > live else f"data files hold {r[0][0] if r else '?'} rows")

say("\n## v3: deletion vectors, row lineage, variant")
b = EXP["t_v3"]["before_variant"]
check("t_v3 at the snapshot before ADD COLUMN payload VARIANT: ids and sum(amount_krw)",
      f"SELECT groupArray(id), sum(amount_krw) FROM (SELECT id, amount_krw FROM {src('t_v3')} ORDER BY id) "
      f"SETTINGS iceberg_snapshot_id = {b['snapshot_id']}", [b["ids"], float(b["sum_amount"])], ids_sum)
check("t_v3 at that snapshot: _row_id, _last_updated_sequence_number",
      f"SELECT id, _row_id, _last_updated_sequence_number FROM {src('t_v3')} ORDER BY id "
      f"SETTINGS iceberg_snapshot_id = {b['snapshot_id']}", b["lineage"])
check("t_v3 current snapshot (payload VARIANT added by ALTER TABLE ADD COLUMN): ids",
      f"SELECT groupArray(id) FROM (SELECT id FROM {src('t_v3')} ORDER BY id)", EXP["t_v3"]["ids"], ids)
check("t_v3 current snapshot, only the file written after ADD COLUMN (WHERE id = 11)",
      f"SELECT groupArray(id) FROM (SELECT id FROM {src('t_v3')} WHERE id = 11)", [11], ids)
check("t_v3_variant (payload VARIANT from CREATE): ids",
      f"SELECT groupArray(id) FROM (SELECT id FROM {src('t_v3_variant')} ORDER BY id)", EXP["t_v3_variant"]["ids"], ids)
check("t_v3_variant: payload type",
      f"SELECT DISTINCT toTypeName(payload) FROM {src('t_v3_variant')}", [["Dynamic"]])
e = EXP["t_v2_to_v3"]
check("t_v2_to_v3 (upgraded, old position delete merged into a deletion vector): ids",
      f"SELECT groupArray(id) FROM (SELECT id FROM {src('t_v2_to_v3')} ORDER BY id)", e["ids"], ids)
check("t_v2_to_v3: _row_id, _last_updated_sequence_number",
      f"SELECT id, _row_id, _last_updated_sequence_number FROM {src('t_v2_to_v3')} ORDER BY id", e["lineage"])

say("\n## through the REST catalog (DataLakeCatalog)")
ch("DROP DATABASE IF EXISTS lake")
ch("CREATE DATABASE lake ENGINE = DataLakeCatalog('http://iceberg-rest:8181') SETTINGS catalog_type = 'rest', "
   f"warehouse = 'warehouse', vended_credentials = 0, aws_access_key_id = 'admin', aws_secret_access_key = 'password123', "
   "region = 'us-east-1', storage_endpoint = 'http://minio:9000/warehouse'")
check("SHOW TABLES FROM lake", "SHOW TABLES FROM lake", sorted(f"fv.{t}" for t in EXP),
      lambda rows: sorted(r[0] for r in rows))
check("lake.`fv.t_v2`: ids", "SELECT groupArray(id) FROM (SELECT id FROM lake.`fv.t_v2` ORDER BY id)", EXP["t_v2"]["ids"], ids)

say(f"\nsummary: {counts['MATCH']} match, {counts['DIFF']} diff, {counts['ERROR']} error")
out = os.path.join(LAB, "results", f"clickhouse-{version}.txt")
open(out, "w").write("\n".join(lines) + "\n")
print(f"wrote {out}", file=sys.stderr)
