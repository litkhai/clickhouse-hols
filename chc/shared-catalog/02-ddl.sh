#!/usr/bin/env bash
# 02 — The DDL matrix of the 2026-10-13 hand run, as a script: engine choice,
# CTAS, cross-database RENAME/EXCHANGE, DETACH, ON CLUSTER, ALTER, table engines.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
# where is a table, per replica: 1 = exists on that replica
where() { show "SELECT hostName() AS replica, countIf(database = '$1' AND name = '$2') AS exists, anyIf(engine, database = '$1' AND name = '$2') AS engine, anyIf(toString(uuid), database = '$1' AND name = '$2') AS uuid FROM clusterAllReplicas('default', system.tables) GROUP BY replica ORDER BY replica"; }

echo "## databases"
expect_ok  db_create   "CREATE DATABASE IF NOT EXISTS sc_lab"
expect_ok  db_create2  "CREATE DATABASE IF NOT EXISTS sc_lab2"
show "SELECT hostName() AS replica, name, engine, uuid FROM clusterAllReplicas('default', system.databases) WHERE name LIKE 'sc_lab%' ORDER BY name, replica"
expect_err db_atomic     344 "CREATE DATABASE sc_lab_atomic ENGINE = Atomic"
expect_err db_replicated 344 "CREATE DATABASE sc_lab_repl ENGINE = Replicated('/clickhouse/databases/sc_lab_repl', '{shard}', '{replica}')"

echo "## CTAS: a failed fill leaves nothing behind"
try ctas_fail "CREATE TABLE sc_lab.ctas_fail ENGINE = MergeTree ORDER BY n AS SELECT number AS n, throwIf(number = 3000000) AS x FROM numbers(5000000) SETTINGS max_block_size = 65536"
where sc_lab ctas_fail
expect_ok ctas_ok "CREATE TABLE sc_lab.ctas ENGINE = MergeTree ORDER BY n AS SELECT number AS n, toString(number) AS s FROM numbers(5000000)"
show "SELECT hostName() AS replica, count() AS rows FROM clusterAllReplicas('default', sc_lab.ctas) GROUP BY replica ORDER BY replica"

echo "## CTAS in flight: is the INTENTION table visible?"
( ch --log_comment="$LAB_TAG:ctas_slow" -q "CREATE TABLE sc_lab.ctas_slow ENGINE = MergeTree ORDER BY n AS SELECT number AS n FROM numbers(6) WHERE sleepEachRow(1) = 0 SETTINGS max_block_size = 1" >/dev/null 2>&1 ) &
pid=$!; sleep 2.5
echo "-- 2.5 s into a 6 s CTAS:"
where sc_lab ctas_slow
try ctas_slow_select "SELECT count() FROM sc_lab.ctas_slow"
wait $pid; echo "-- after it returned:"
where sc_lab ctas_slow

echo "## cross-database RENAME and EXCHANGE"
expect_ok other "CREATE TABLE sc_lab.other (n UInt64) ENGINE = MergeTree ORDER BY n"
expect_ok other_fill "INSERT INTO sc_lab.other SELECT number FROM numbers(10)"
where sc_lab ctas
expect_ok rename_xdb "RENAME TABLE sc_lab.ctas TO sc_lab2.moved"
where sc_lab2 moved
expect_ok exchange_xdb "EXCHANGE TABLES sc_lab.other AND sc_lab2.moved"
show "SELECT 'sc_lab.other' AS t, count() AS rows FROM sc_lab.other UNION ALL SELECT 'sc_lab2.moved', count() FROM sc_lab2.moved"
expect_ok rename_db "RENAME DATABASE sc_lab2 TO sc_lab3"
show "SELECT hostName() AS replica, name, uuid FROM clusterAllReplicas('default', system.databases) WHERE name LIKE 'sc_lab%' ORDER BY name, replica"
expect_ok rename_db_back "RENAME DATABASE sc_lab3 TO sc_lab2"

echo "## DETACH"
expect_ok det_t "CREATE TABLE sc_lab.det (n UInt64) ENGINE = MergeTree ORDER BY n"
try det_plain "DETACH TABLE sc_lab.det"
expect_ok det_perm "DETACH TABLE sc_lab.det PERMANENTLY"
show "SELECT hostName() AS replica, database, table, is_permanently FROM clusterAllReplicas('default', system.detached_tables) WHERE database = 'sc_lab' ORDER BY replica"
expect_ok attach "ATTACH TABLE sc_lab.det"
where sc_lab det

echo "## ON CLUSTER"
expect_ok oc_default "CREATE TABLE sc_lab.oc_default ON CLUSTER default (n UInt64) ENGINE = MergeTree ORDER BY n"
where sc_lab oc_default
try oc_all_groups "CREATE TABLE sc_lab.oc_all ON CLUSTER 'all_groups.default' (n UInt64) ENGINE = MergeTree ORDER BY n" --distributed_ddl_task_timeout=20 --distributed_ddl_output_mode=throw
where sc_lab oc_all
show "SELECT entry, host, status, exception_code, substring(exception_text, 1, 90) AS exception FROM system.distributed_ddl_queue WHERE query LIKE '%sc_lab.oc_all%' ORDER BY entry DESC, host LIMIT 6"
expect_err oc_missing 701 "CREATE TABLE sc_lab.oc_x ON CLUSTER no_such_cluster (n UInt64) ENGINE = MergeTree ORDER BY n"

echo "## ALTER reaches every replica before the statement returns"
expect_ok alter_add "ALTER TABLE sc_lab.other ADD COLUMN c String DEFAULT 'x'"
show "SELECT hostName() AS replica, groupArray(name) AS columns FROM clusterAllReplicas('default', system.columns) WHERE database = 'sc_lab' AND table = 'other' GROUP BY replica ORDER BY replica"

echo "## table engines in a Shared database"
for e in Log TinyLog StripeLog "EmbeddedRocksDB PRIMARY KEY n"; do
  try "engine_${e%% *}" "CREATE TABLE sc_lab.e_${e%% *} (n UInt64) ENGINE = $e"
done
expect_ok e_rmt     "CREATE TABLE sc_lab.e_rmt (n UInt64) ENGINE = ReplicatedMergeTree ORDER BY n"
try       e_rmt_arg "CREATE TABLE sc_lab.e_rmt_arg (n UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/x/e_rmt_arg', 'r1') ORDER BY n"
try       e_rmt_mac "CREATE TABLE sc_lab.e_rmt_mac (n UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/e_rmt_mac', '{replica}') ORDER BY n"
echo "-- the full message of e_rmt_mac:"; ch -q "CREATE TABLE sc_lab.e_rmt_mac2 (n UInt64) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/e_rmt_mac2', '{replica}') ORDER BY n" 2>&1 | grep -oE 'It.s not allowed.*' | cut -c1-300 || true
expect_ok e_set     "CREATE TABLE sc_lab.e_set (n UInt64) ENGINE = Set"
expect_ok e_join    "CREATE TABLE sc_lab.e_join (n UInt64, v String) ENGINE = Join(ANY, LEFT, n)"
expect_ok e_memory  "CREATE TABLE sc_lab.e_memory (n UInt64) ENGINE = Memory"
expect_ok e_null    "CREATE TABLE sc_lab.e_null (n UInt64) ENGINE = Null"
expect_ok e_view    "CREATE VIEW sc_lab.e_view AS SELECT n FROM sc_lab.other"
expect_ok e_mv      "CREATE MATERIALIZED VIEW sc_lab.e_mv ENGINE = MergeTree ORDER BY n AS SELECT n FROM sc_lab.other"
show "SELECT name, engine, substring(engine_full, 1, 110) AS engine_full FROM system.tables WHERE database = 'sc_lab' AND (name LIKE 'e\\_%' OR name LIKE '.inner%') ORDER BY name"
echo "-- Set/Join/Memory: insert 100 rows on one connection, count on every replica"
expect_ok fill_set    "INSERT INTO sc_lab.e_set SELECT number FROM numbers(100)"
expect_ok fill_join   "INSERT INTO sc_lab.e_join SELECT number, toString(number) FROM numbers(100)"
expect_ok fill_memory "SELECT hostName() AS inserted_on; INSERT INTO sc_lab.e_memory SELECT number FROM numbers(100)" --multiquery
sleep 3
show "SELECT hostName() AS replica, name, engine, total_rows FROM clusterAllReplicas('default', system.tables) WHERE database = 'sc_lab' AND name IN ('e_memory', 'e_set', 'e_join') ORDER BY name, replica"
echo "## SHOW CREATE: the catalog keeps the engine with its Keeper path"
show "SELECT replaceRegexpOne(create_table_query, '^.*ENGINE', 'ENGINE') AS stored FROM system.tables WHERE database = 'sc_lab' AND name = 'other' FORMAT Vertical"
