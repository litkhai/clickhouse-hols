#!/usr/bin/env bash
# 04 — How fast a committed DDL reaches the other replica: the executing replica
# logs "... at global version G"; every other replica logs when it applied a
# state >= G. An ASOF join pairs them. Plus server-side DDL time from query_log.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
N="${PROP_ROUNDS:-10}"
START="${PROP_START:-$(ch -q "SELECT now64(6)" 2>/dev/null | grep -v '^Unknown')}"
echo "start = $START, rounds = $N (CREATE, ALTER, RENAME, DROP each, one connection per statement)"
[ -n "${PROP_START:-}" ] || for i in $(seq 1 "$N"); do
  ch --log_comment="$LAB_TAG:prop:create" -q "CREATE TABLE sc_lab.p$i (n UInt64) ENGINE = MergeTree ORDER BY n" 2>/dev/null
  ch --log_comment="$LAB_TAG:prop:alter"  -q "ALTER TABLE sc_lab.p$i ADD COLUMN c UInt8" 2>/dev/null
  ch --log_comment="$LAB_TAG:prop:rename" -q "RENAME TABLE sc_lab.p$i TO sc_lab.q$i" 2>/dev/null
  ch --log_comment="$LAB_TAG:prop:drop"   -q "DROP TABLE sc_lab.q$i SYNC" 2>/dev/null
done
sleep 2; flush_logs
cat > "$LAB_DIR/out/.prop.sql" <<SQL
WITH commits AS (
  SELECT hostName() AS executor, event_time_microseconds AS committed_at,
         toUInt64(extract(message, 'at global version ([0-9]+)')) AS version,
         multiIf(message LIKE 'Successfully committed intentions%', 'create', message LIKE 'Successfully altered%', 'alter',
                 message LIKE 'Successfully renamed%', 'rename', message LIKE '%marked as dropped%', 'drop', 'other') AS ddl
  FROM clusterAllReplicas('default', system.text_log)
  WHERE event_time_microseconds >= '$START' AND logger_name = 'SharedDatabaseCatalog'
    AND message LIKE '%at global version%' AND message LIKE '%sc_lab.%'
  ORDER BY committed_at LIMIT 1 BY version
),
targets AS (
  SELECT c.*, t AS target FROM commits AS c
  ARRAY JOIN (SELECT groupUniqArray(hostName()) FROM clusterAllReplicas('default', system.one)) AS t
  WHERE t != c.executor
),
applies AS (
  SELECT hostName() AS replica, event_time_microseconds AS applied_at,
         toUInt64(extract(message, 'with version ([0-9]+)')) AS version,
         toFloat64(extract(message, 'in ([0-9.]+) seconds')) AS apply_s
  FROM clusterAllReplicas('default', system.text_log)
  WHERE event_time_microseconds >= '$START' AND logger_name = 'SharedDatabaseCatalog'
    AND message LIKE 'applyState: Successfully applied state with version%'
),
pairs AS (
  SELECT c.ddl, c.executor, a.replica, c.version, a.version AS applied_version,
         dateDiff('microsecond', c.committed_at, a.applied_at) / 1000 AS lag_ms, a.apply_s * 1000 AS apply_ms
  FROM targets AS c ASOF INNER JOIN applies AS a ON a.replica = c.target AND a.version >= c.version
)
SELECT ddl, count() AS n, round(quantile(0.5)(lag_ms), 1) AS p50_lag_ms, round(quantile(0.9)(lag_ms), 1) AS p90_lag_ms,
       round(max(lag_ms), 1) AS max_lag_ms, round(quantile(0.5)(apply_ms), 1) AS p50_apply_ms,
       countIf(applied_version > version) AS batched_with_later
FROM pairs GROUP BY ddl ORDER BY ddl
SQL
echo "## commit on one replica → applied on the other (from text_log)"
show "$(cat "$LAB_DIR/out/.prop.sql")"
echo "## server-side time of the same DDLs (query_log): each DDL logs twice, the inner"
echo "## statement the catalog rewrites (UUID filled in) and the outer one the client sent;"
echo "## outer - inner = waiting for the other replicas (distributed_ddl_output_mode)"
show "SELECT ddl, count() AS n, quantile(0.5)(inner_ms) AS p50_inner_ms, quantile(0.5)(outer_ms) AS p50_outer_ms, quantile(0.5)(outer_ms - inner_ms) AS p50_wait_ms, max(outer_ms) AS max_outer_ms FROM (SELECT ddl, intDiv(rn - 1, 2) AS k, minIf(ms, rn % 2 = 1) AS inner_ms, minIf(ms, rn % 2 = 0) AS outer_ms FROM (SELECT extract(log_comment, 'prop:(.*)') AS ddl, query_duration_ms AS ms, row_number() OVER (PARTITION BY ddl ORDER BY event_time_microseconds) AS rn FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$START' AND type = 'QueryFinish' AND log_comment LIKE '$LAB_TAG:prop:%') GROUP BY ddl, k) GROUP BY ddl ORDER BY ddl"
echo "## which replica ran them"
show "SELECT hostName() AS replica, intDiv(count(), 2) AS ddls FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$START' AND type = 'QueryFinish' AND log_comment LIKE '$LAB_TAG:prop:%' GROUP BY replica ORDER BY replica"
echo "## what one state fetch costs on the receiving side"
show "SELECT hostName() AS replica, count() AS fetches, round(avg(toUInt32OrZero(extract(message, 'fetched ([0-9]+)'))), 1) AS avg_objects_fetched, max(toUInt32OrZero(extract(message, 'UUIDs size ([0-9]+)'))) AS uuids_in_state, quantile(0.5)(toUInt32OrZero(extract(message, 'ZK query in ([0-9]+) ms'))) AS p50_zk_ms FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$START' AND logger_name = 'SharedDatabaseCatalog' AND message LIKE 'Successfully fetched state % UUIDs size%' GROUP BY replica ORDER BY replica"
