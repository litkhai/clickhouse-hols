#!/usr/bin/env bash
# Shared-catalog OSS lab: where does the catalog live? (clickhouse-hols#134)
# Usage: ./run.sh        run all steps, outputs in out/
#        ./run.sh down   remove containers and volumes
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out

if [ "${1:-}" = down ]; then docker compose down -v; exit 0; fi

# ---- helpers ---------------------------------------------------------------
cli() { local h=$1; shift; docker compose exec -T "$h" clickhouse-client --multiquery "$@"; }

# q HOST SQL : print the statement, then the result
q() {
  local h=$1 sql=$2; shift 2
  echo "-- [$h] $sql"
  cli "$h" "$@" -q "$sql" 2>&1 | sed 's/^/   /'
  [ "${PIPESTATUS[0]}" = 0 ] || { echo "UNEXPECTED FAILURE"; exit 1; }
}
# qv HOST SQL : same, raw (multi-line values kept)
qv() { q "$1" "$2" --format TSVRaw; }
# err HOST SQL : must fail; prints code + message
err() {
  local h=$1 sql=$2 out
  echo "-- [$h] (expected to fail) $sql"
  if out=$(cli "$h" -q "$sql" 2>&1); then
    echo "   UNEXPECTEDLY SUCCEEDED: $out"; exit 1
  fi
  echo "$out" | grep -m1 -o 'Code: [0-9]*\. DB::Exception: .*' | sed 's/^/   /'
}
# try HOST SQL : may succeed or fail; prints whichever happened
try() {
  local h=$1 sql=$2 out
  echo "-- [$h] (outcome not asserted) $sql"
  if out=$(cli "$h" -q "$sql" 2>&1); then echo "   SUCCEEDED: $out"
  else echo "   FAILED: $(echo "$out" | grep -m1 -o 'Code: [0-9]*\. DB::Exception: .*')"; fi
}
# zk PATH DEPTH : walk system.zookeeper (name, numChildren, value cut to 110 chars)
zk() {
  local p=$1 d=$2 ind=${3:-}
  [ -z "$ind" ] && { echo "-- [ch1] system.zookeeper tree of $p (depth $d)"; }
  local rows
  rows=$(cli ch1 --format TSVRaw -q "SELECT name, numChildren, replaceAll(substring(value,1,110),char(10),'\\\\n') FROM system.zookeeper WHERE path='$p' ORDER BY name" </dev/null 2>&1)
  while IFS=$'\t' read -r name nc val; do
    [ -z "$name" ] && continue
    echo "   $ind$name  [children=$nc]${val:+  = $val}"
    if [ "$nc" != 0 ] && [ "$d" -gt 1 ]; then zk "$p/$name" $((d-1)) "$ind  "; fi
  done <<< "$rows"
}
sh() { echo "-- [$1] $2"; docker compose exec -T "$1" bash -c "$2" 2>&1 | sed 's/^/   /'; }
wait_until() { # HOST SQL expected(seconds 120)
  for _ in $(seq 60); do
    [ "$(cli "$1" -q "$2" 2>/dev/null || true)" = "$3" ] && return 0; sleep 2
  done; echo "TIMEOUT waiting for: $2 = $3"; exit 1; }
cleanup_state() {
  for h in ch1 ch2; do cli $h -q "DROP DATABASE IF EXISTS analytics SYNC; DROP DATABASE IF EXISTS rdb SYNC; DROP DATABASE IF EXISTS rdb2 SYNC" >/dev/null 2>&1 || true; done
}

# ---- start -----------------------------------------------------------------
docker compose up -d
wait_until ch1 "SELECT 1" 1; wait_until ch2 "SELECT 1" 1
cleanup_state
echo "run date: $(date -u +%F\ %T) UTC" | tee out/00-version.txt
q ch1 "SELECT version()" | tee -a out/00-version.txt
q ch2 "SELECT version()" | tee -a out/00-version.txt
docker compose images | tee -a out/00-version.txt

# ---- step 1 ----------------------------------------------------------------
step1() {
echo "=== 1. Atomic database + ReplicatedMergeTree ==="
q ch1 "CREATE DATABASE analytics"
q ch2 "CREATE DATABASE analytics"
q ch1 "SELECT name, engine FROM system.databases WHERE name='analytics'"
q ch1 "CREATE TABLE analytics.events (id UInt64, ts DateTime) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events','{replica}') ORDER BY id"
q ch2 "SHOW TABLES FROM analytics"
zk /clickhouse/tables/01/events 3
qv ch1 "SELECT value FROM system.zookeeper WHERE path='/clickhouse/tables/01/events' AND name='metadata'"
qv ch1 "SELECT value FROM system.zookeeper WHERE path='/clickhouse/tables/01/events' AND name='columns'"
echo "-- local side on ch1"
sh ch1 "cat /var/lib/clickhouse/metadata/analytics/events.sql"
sh ch1 "ls -l /var/lib/clickhouse/metadata/ /var/lib/clickhouse/metadata/analytics | grep -v '^total'"
sh ch1 "ls -l /var/lib/clickhouse/data/ | grep analytics; ls /var/lib/clickhouse/store/*/*/ | head"
q ch1 "SELECT name, uuid, data_paths, metadata_path FROM system.tables WHERE database='analytics' FORMAT Vertical"
echo "--- create the same table on ch2"
q ch2 "CREATE TABLE analytics.events (id UInt64, ts DateTime) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events','{replica}') ORDER BY id"
zk /clickhouse/tables/01/events/replicas 1
echo "--- ALTER on ch1 only (no ON CLUSTER)"
q ch1 "ALTER TABLE analytics.events ADD COLUMN note String"
q ch2 "SHOW CREATE TABLE analytics.events FORMAT TSVRaw"
sh ch2 "cat /var/lib/clickhouse/metadata/analytics/events.sql"
qv ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/tables/01/events/log'"
echo "--- RENAME on ch1"
q ch1 "RENAME TABLE analytics.events TO analytics.events_renamed"
q ch1 "SELECT \`table\`, zookeeper_path, replica_name FROM system.replicas WHERE database='analytics'"
q ch2 "SHOW TABLES FROM analytics"
zk /clickhouse/tables/01 1
echo "--- DROP on ch1"
q ch1 "DROP TABLE analytics.events_renamed SYNC"
zk /clickhouse/tables/01/events/replicas 1
q ch2 "SELECT name FROM system.tables WHERE database='analytics'"
echo "--- plain view on ch1"
q ch1 "CREATE VIEW analytics.plain_view_probe AS SELECT 1 AS x"
echo "-- [ch1] search for the view name in the Keeper tree under /clickhouse (depth 5, names and first 110 chars of values):"
echo "   matching lines: $(zk /clickhouse 5 | grep -c plain_view_probe || true)"
zk /clickhouse 3
sh ch1 "cat /var/lib/clickhouse/metadata/analytics/plain_view_probe.sql"
q ch2 "SHOW TABLES FROM analytics"
}
step1 2>&1 | tee out/step1.txt

# ---- step 2 ----------------------------------------------------------------
step2() {
echo "=== 2. ON CLUSTER (DDLWorker queue) ==="
q ch1 "CREATE TABLE analytics.t_cluster ON CLUSTER c (id UInt64) ENGINE = MergeTree ORDER BY id" --format TSVWithNames
zk /clickhouse/task_queue/ddl 3
qv ch1 "SELECT value FROM system.zookeeper WHERE path='/clickhouse/task_queue/ddl' AND name='query-0000000000'"
q ch2 "SELECT name FROM system.tables WHERE database='analytics' AND name='t_cluster'"
q ch1 "SELECT name, value, changed FROM system.server_settings WHERE name LIKE '%ddl%' OR name LIKE '%task%'"
echo "--- stop ch2, run another ON CLUSTER DDL with distributed_ddl_task_timeout=10"
echo "-- docker compose stop ch2"; docker compose stop ch2 2>&1 | sed 's/^/   /'
err ch1 "CREATE TABLE analytics.t_late ON CLUSTER c (id UInt64) ENGINE = MergeTree ORDER BY id SETTINGS distributed_ddl_task_timeout=10"
q ch1 "SELECT name FROM system.tables WHERE database='analytics' AND name='t_late'"
zk /clickhouse/task_queue/ddl 3
qv ch1 "SELECT value FROM system.zookeeper WHERE path='/clickhouse/task_queue/ddl' AND name='query-0000000001'"
echo "-- docker compose start ch2"; docker compose start ch2 2>&1 | sed 's/^/   /'
wait_until ch2 "SELECT count() FROM system.tables WHERE database='analytics' AND name='t_late'" 1
q ch2 "SELECT name FROM system.tables WHERE database='analytics' ORDER BY name"
zk /clickhouse/task_queue/ddl/query-0000000001 2
}
step2 2>&1 | tee out/step2.txt

# ---- step 3 ----------------------------------------------------------------
step3() {
echo "=== 3. Replicated database ==="
q ch1 "CREATE DATABASE rdb ENGINE = Replicated('/clickhouse/databases/rdb','{shard}','{replica}')"
q ch2 "CREATE DATABASE rdb ENGINE = Replicated('/clickhouse/databases/rdb','{shard}','{replica}')"
q ch1 "CREATE TABLE rdb.t (id UInt64, v String) ENGINE = ReplicatedMergeTree ORDER BY id"
q ch1 "CREATE VIEW rdb.v AS SELECT id FROM rdb.t"
q ch2 "SYSTEM SYNC DATABASE REPLICA rdb"
q ch2 "SHOW TABLES FROM rdb"
q ch2 "SELECT name, engine, create_table_query FROM system.tables WHERE database='rdb' ORDER BY name FORMAT Vertical"
zk /clickhouse/databases/rdb 3
for n in $(cli ch1 -q "SELECT name FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/metadata' ORDER BY name"); do
  qv ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/metadata' AND name='$n'"
done
for n in $(cli ch1 -q "SELECT name FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/log' ORDER BY name"); do
  qv ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/log' AND name='$n'"
done
for r in $(cli ch1 -q "SELECT name FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/replicas' ORDER BY name"); do
  qv ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb/replicas/$r' AND name IN ('log_ptr','digest','active') ORDER BY name"
done
sh ch1 "ls /var/lib/clickhouse/metadata/ ; cat /var/lib/clickhouse/metadata/rdb.sql; ls /var/lib/clickhouse/metadata/rdb"
}
step3 2>&1 | tee out/step3.txt

# ---- step 4 ----------------------------------------------------------------
step4() {
echo "=== 4. Replicated database limits ==="
err ch1 "RENAME TABLE rdb.t TO analytics.t"
q ch1 "CREATE TABLE rdb.tmp (id UInt64) ENGINE = MergeTree ORDER BY id"
q ch1 "DROP TABLE rdb.tmp"
err ch1 "UNDROP TABLE rdb.tmp"
q ch1 "SELECT name, value, changed, description FROM system.settings WHERE name = 'database_replicated_allow_heavy_create' FORMAT Vertical"
try ch1 "CREATE TABLE rdb.ctas ENGINE = MergeTree ORDER BY id AS SELECT number AS id FROM numbers(3)"
try ch1 "CREATE TABLE rdb.ctas2 ENGINE = MergeTree ORDER BY id AS SELECT number AS id FROM numbers(3) SETTINGS database_replicated_allow_heavy_create=0"
q ch2 "SELECT database, name, create_table_query FROM system.tables WHERE database='rdb' AND name LIKE 'ctas%' FORMAT Vertical"
# The block is for replicated target engines; a plain MergeTree CTAS is re-run by every replica
err ch1 "CREATE TABLE rdb.ctas_rmt ENGINE = ReplicatedMergeTree ORDER BY id AS SELECT number AS id FROM numbers(3)"
for h in ch1 ch2; do q $h "SELECT hostName() AS replica, name, engine, total_rows FROM system.tables WHERE database='rdb' AND name LIKE 'ctas%' ORDER BY name"; done
try ch1 "CREATE TABLE rdb.oc ON CLUSTER c (id UInt64) ENGINE = MergeTree ORDER BY id"
q ch1 "SHOW TABLES FROM rdb"
q ch2 "SHOW TABLES FROM rdb"
q ch1 "SYSTEM SYNC DATABASE REPLICA rdb"
q ch2 "SYSTEM SYNC DATABASE REPLICA rdb"
}
step4 2>&1 | tee out/step4.txt

# ---- step 5 ----------------------------------------------------------------
step5() {
echo "=== 5a. Drop and recreate one replica of a Replicated database ==="
zk /clickhouse/databases/rdb/replicas 1
q ch2 "DROP DATABASE rdb SYNC"
zk /clickhouse/databases/rdb/replicas 1
q ch1 "SHOW TABLES FROM rdb"
q ch2 "CREATE DATABASE rdb ENGINE = Replicated('/clickhouse/databases/rdb','{shard}','{replica}')"
q ch2 "SYSTEM SYNC DATABASE REPLICA rdb"
q ch2 "SHOW TABLES FROM rdb"
zk /clickhouse/databases/rdb/replicas 1
q ch2 "SYSTEM FLUSH LOGS"
q ch2 "SHOW DATABASES"
q ch2 "SELECT event_time, logger_name, message FROM system.text_log WHERE logger_name LIKE 'DatabaseReplicated (rdb)%' AND event_time > now() - 600 ORDER BY event_time_microseconds LIMIT 60 FORMAT TSVRaw"

echo; echo "=== 5b. Lost replica with local divergence (logs_to_keep=5) ==="
q ch1 "CREATE DATABASE rdb2 ENGINE = Replicated('/clickhouse/databases/rdb2','{shard}','{replica}') SETTINGS logs_to_keep=5"
q ch2 "CREATE DATABASE rdb2 ENGINE = Replicated('/clickhouse/databases/rdb2','{shard}','{replica}')"
qv ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb2' AND name='logs_to_keep'"
q ch1 "CREATE TABLE rdb2.local (a UInt32) ENGINE = MergeTree ORDER BY a"
q ch2 "SYSTEM SYNC DATABASE REPLICA rdb2"
q ch2 "INSERT INTO rdb2.local SELECT number FROM numbers(5)"
q ch2 "SELECT 'ch2 local rows', count() FROM rdb2.local"
q ch1 "SELECT 'ch1 local rows', count() FROM rdb2.local"
zk /clickhouse/databases/rdb2/replicas 2
echo "-- docker compose stop ch2"; docker compose stop ch2 2>&1 | sed 's/^/   /'
q ch1 "DROP TABLE rdb2.local SYNC" --distributed_ddl_task_timeout=0
q ch1 "CREATE TABLE rdb2.local (b String, c Float64) ENGINE = MergeTree ORDER BY b" --distributed_ddl_task_timeout=0
for i in $(seq 1 12); do cli ch1 --distributed_ddl_task_timeout=0 -q "CREATE TABLE rdb2.filler_$i (x UInt8) ENGINE = MergeTree ORDER BY x; DROP TABLE rdb2.filler_$i SYNC"; done
echo "-- [ch1] 24 filler DDLs run (12 x CREATE + DROP)"
q ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb2' AND name IN ('max_log_ptr','logs_to_keep') ORDER BY name"
q ch1 "SELECT name, value FROM system.zookeeper WHERE path='/clickhouse/databases/rdb2/replicas/01|ch2' AND name='log_ptr'"
q ch1 "SELECT count(), min(name), max(name) FROM system.zookeeper WHERE path='/clickhouse/databases/rdb2/log'"
echo "-- docker compose start ch2"; docker compose start ch2 2>&1 | sed 's/^/   /'
wait_until ch2 "SELECT 1" 1
sleep 20
q ch2 "SYSTEM SYNC DATABASE REPLICA rdb2"
q ch2 "SHOW DATABASES"
q ch2 "SELECT database, name, engine, create_table_query FROM system.tables WHERE database LIKE 'rdb2%' ORDER BY database, name FORMAT Vertical"
for db in $(cli ch2 -q "SELECT name FROM system.databases WHERE name LIKE '%broken%'"); do
  q ch2 "SELECT 'rows in $db tables', database, table, sum(rows) FROM system.parts WHERE database='$db' AND active GROUP BY database, table"
done
q ch2 "SELECT 'rdb2.local rows', count() FROM rdb2.local"
q ch2 "SYSTEM FLUSH LOGS"
q ch2 "SELECT event_time, logger_name, message FROM system.text_log WHERE (logger_name LIKE 'DatabaseReplicated (rdb2)%' OR message ILIKE '%rdb2_broken%' OR message ILIKE '%rdb2.local%') AND logger_name != 'AsyncLoader' AND logger_name != 'executeQuery' AND event_time > now() - 900 ORDER BY event_time_microseconds LIMIT 60 FORMAT TSVRaw"
zk /clickhouse/databases/rdb2/replicas 2
}
step5 2>&1 | tee out/step5.txt
echo "ALL STEPS DONE"
