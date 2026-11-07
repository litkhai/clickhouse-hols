#!/usr/bin/env bash
# 06 — Does a bigger catalog make DDL slower? Time CREATE TABLE and the other
# replica's state application with the service's catalog as it is, then after
# adding SCALE_N empty tables (default 800), then drop them all.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
SN="${SCALE_N:-800}"
objects() { ch -q "SELECT value FROM system.metrics WHERE name = 'SharedCatalogNumberOfObjectsInState'" 2>/dev/null | grep -v '^Unknown'; }
probe() { # probe TAG: 20 CREATE+DROP SYNC pairs on separate connections, report CREATE timing
  local tag="$1" i s
  s="$(ch -q "SELECT now64(6)" 2>/dev/null | grep -v '^Unknown')"
  for i in $(seq 1 20); do
    ch --log_comment="$LAB_TAG:scale:$tag" -q "CREATE TABLE sc_lab.probe_$i (n UInt64) ENGINE = MergeTree ORDER BY n" 2>/dev/null
    ch -q "DROP TABLE sc_lab.probe_$i SYNC" 2>/dev/null
  done
  sleep 2; flush_logs
  show "SELECT '$tag' AS catalog, $(objects) AS objects_now, count() AS creates, quantile(0.5)(query_duration_ms) AS p50_ms, quantile(0.9)(query_duration_ms) AS p90_ms FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$s' AND type = 'QueryFinish' AND log_comment = '$LAB_TAG:scale:$tag' AND query NOT LIKE '% UUID %'"
  show "SELECT '$tag' AS catalog, hostName() AS replica, countIf(message LIKE 'applyState%') AS applies, round(quantileIf(0.5)(toFloat64OrZero(extract(message, 'in ([0-9.]+) seconds')), message LIKE 'applyState%') * 1000, 1) AS p50_apply_ms, max(toUInt32OrZero(extract(message, 'UUIDs size ([0-9]+)'))) AS uuids FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$s' AND logger_name = 'SharedDatabaseCatalog' AND (message LIKE 'applyState: Successfully applied state%' OR message LIKE 'Successfully fetched state % UUIDs size%') GROUP BY replica ORDER BY replica"
}
echo "## objects before: $(objects)"
probe base
expect_ok mkdb "CREATE DATABASE IF NOT EXISTS sc_scale"
echo "## creating $SN empty tables over one connection"
t0=$(date +%s)
for i in $(seq 1 "$SN"); do echo "CREATE TABLE sc_scale.t$i (n UInt64, s String) ENGINE = MergeTree ORDER BY n;"; done > "$LAB_DIR/out/.scale.sql"
ch --log_comment="$LAB_TAG:scale:bulk" --queries-file "$LAB_DIR/out/.scale.sql" 2>/dev/null
echo "bulk create: $(( $(date +%s) - t0 )) s wall, objects now $(objects)"
probe big
echo "## drop the database with $SN tables"
try dropdb_scale "DROP DATABASE sc_scale SYNC" --distributed_ddl_task_timeout=600
sleep 2; flush_logs
show "SELECT hostName() AS replica, max(query_duration_ms) AS drop_database_ms FROM clusterAllReplicas('default', system.query_log) WHERE event_time > now() - INTERVAL 10 MINUTE AND type = 'QueryFinish' AND log_comment = '$LAB_TAG:dropdb_scale' GROUP BY replica"
echo "## objects after: $(objects)"
