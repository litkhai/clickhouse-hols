#!/usr/bin/env bash
# 05 — Many small INSERTs: parts, object storage writes and Keeper requests,
# synchronous vs async_insert. Both runs send the same rows from PARALLEL concurrent clients.
#   ROWS=200 single-row INSERTs per run (default), PARALLEL=20
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
# This step reads only log rows written after it started, so re-running it does not mix runs.
T0="$(ch -q "SELECT now64(6)")"
ROWS="${ROWS:-200}"; PARALLEL="${PARALLEL:-20}"
export -f ch
export CH_HOST CH_USER CH_PASSWORD CH_PORT
export CH_CLIENT_STR="${CH_CLIENT_STR:-${CH_CLIENT[*]}}"

for t in small_sync small_async; do
  ch -q "CREATE TABLE IF NOT EXISTS smt_lab.$t (id UInt32, at DateTime64(3) DEFAULT now64(3)) ENGINE = MergeTree ORDER BY id"
  ch -q "TRUNCATE TABLE smt_lab.$t"
done

one() {   # one INSERT of one row: one() TABLE SETTINGS ID
  read -r -a CH_CLIENT <<< "$CH_CLIENT_STR"
  ch -q "INSERT INTO smt_lab.$1 (id) SETTINGS $2 VALUES ($3)" < /dev/null
}
export -f one

start=$(date +%s)
seq 1 "$ROWS" | xargs -P "$PARALLEL" -I{} bash -c 'one small_sync "log_comment = '"'"'lab:small-sync'"'"'" {}'
echo "sync:  $ROWS inserts, $PARALLEL clients, $(( $(date +%s) - start ))s"
start=$(date +%s)
seq 1 "$ROWS" | xargs -P "$PARALLEL" -I{} bash -c 'one small_async "async_insert = 1, wait_for_async_insert = 1, log_comment = '"'"'lab:small-async'"'"'" {}'
echo "async: $ROWS inserts, $PARALLEL clients, $(( $(date +%s) - start ))s"

ch -q "SELECT sleep(3) FORMAT Null"
ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'"
echo

echo "-- Rows arrived, and the parts each run created (NewPart on the writer, before merges)"
show "
SELECT table, countIf(event_type = 'NewPart') AS new_parts, sumIf(rows, event_type = 'NewPart') AS rows,
       countIf(event_type = 'DownloadPart') AS loaded_by_other_replica,
       countIf(event_type = 'MergeParts') AS merges,
       formatReadableSize(sumIf(ProfileEvents['WriteBufferFromS3Bytes'], event_type = 'NewPart')) AS s3_written_by_inserts
FROM clusterAllReplicas('default', system.part_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND database = 'smt_lab' AND table IN ('small_sync', 'small_async')
GROUP BY table
ORDER BY table"

echo
echo "-- The INSERT queries: latency seen by the client, Keeper requests made in the query."
echo "-- With async_insert the buffer flush is a query of its own; it carries the client's log_comment."
show "
SELECT log_comment,
       if(query_id IN (SELECT flush_query_id FROM clusterAllReplicas('default', system.asynchronous_insert_log)
                       WHERE event_date = today() AND database = 'smt_lab'), 'buffer flush', 'client INSERT') AS kind,
       count() AS queries,
       round(quantile(0.5)(query_duration_ms)) AS p50_ms, max(query_duration_ms) AS max_ms,
       sum(ProfileEvents['ZooKeeperTransactions']) AS keeper_requests,
       formatReadableSize(sum(ProfileEvents['WriteBufferFromS3Bytes'])) AS s3_written
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND type = 'QueryFinish' AND log_comment IN ('lab:small-sync', 'lab:small-async')
GROUP BY log_comment, kind
ORDER BY log_comment, kind"

echo
echo "-- async_insert flushes: how many buffers were written, and how many INSERTs each held"
show "
SELECT hostName() AS replica, count() AS inserts, uniqExact(flush_query_id) AS flushes, sum(rows) AS rows,
       round(count() / uniqExact(flush_query_id), 1) AS inserts_per_flush
FROM clusterAllReplicas('default', system.asynchronous_insert_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND database = 'smt_lab' AND table = 'small_async' AND status = 'Ok'
GROUP BY replica
ORDER BY replica"

echo
echo "-- Where the part-count limits sit on this service (not reached here)"
show "
SELECT name, value FROM system.merge_tree_settings
WHERE name IN ('parts_to_delay_insert', 'parts_to_throw_insert', 'max_parts_in_total')
ORDER BY name"
