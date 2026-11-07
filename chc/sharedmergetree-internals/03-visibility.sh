#!/usr/bin/env bash
# 03 — After an INSERT on one replica, when does the other replica see the row?
#
# Each trial is one connection (it lands on either replica): INSERT one row, then at once ask
# every replica, through clusterAllReplicas, whether it sees that row. part_log then gives the
# server-side lag between NewPart on the writer and DownloadPart on the other replica.
#   TRIALS=30 (default)
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
# This step reads only log rows written after it started, so re-running it does not mix runs.
T0="$(ch -q "SELECT now64(6)")"
TRIALS="${TRIALS:-30}"

ch -q "CREATE TABLE IF NOT EXISTS smt_lab.vis (id UInt32, at DateTime64(6) DEFAULT now64(6)) ENGINE = MergeTree ORDER BY id"
ch -q "TRUNCATE TABLE smt_lab.vis"

base=$(( $(date +%s) % 100000 * 100 ))
# trials SSC: the check query runs with select_sequential_consistency = SSC
trials() {
  local ssc="$1" i id out writer other seen=0
  echo "-- check with select_sequential_consistency = $ssc"
  echo "trial  writer     other replica sees the row"
  for i in $(seq 1 "$TRIALS"); do
    id=$((base + ssc * 1000 + i))
    # stdin from /dev/null: with an open stdin the client waits for INSERT data there
    out="$(ch --multiquery --format TSV -q "
      INSERT INTO smt_lab.vis (id) SETTINGS log_comment = 'lab:vis-insert' VALUES ($id);
      SELECT 'writer', hostName();
      SELECT hostName(), countIf(id = $id) FROM clusterAllReplicas('default', smt_lab.vis)
        GROUP BY hostName() SETTINGS log_comment = 'lab:vis-check$ssc', select_sequential_consistency = $ssc;" < /dev/null)"
    writer="$(awk -F'\t' '$1 == "writer" { print $2 }' <<< "$out")"
    other="$(awk -F'\t' -v w="$writer" '$1 != "writer" && $1 != w { print $2 }' <<< "$out")"
    if [ "${other:-0}" = "1" ]; then seen=$((seen + 1)); fi
    printf '%5d  %s  %s\n' "$i" "$writer" "${other:-?}"
  done
  echo "other replica saw the row in the first check: $seen of $TRIALS trials (select_sequential_consistency = $ssc)"
  echo
}
trials 0
trials 1

ch -q "SELECT sleep(3) FORMAT Null"
ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'"

echo "-- Lag between NewPart on the writer and DownloadPart on the other replica, inserted parts only (part_log, server clocks)"
show "
SELECT count() AS parts,
       round(min(lag_ms), 1) AS min_ms, round(quantile(0.5)(lag_ms), 1) AS p50_ms,
       round(quantile(0.9)(lag_ms), 1) AS p90_ms, round(max(lag_ms), 1) AS max_ms
FROM (
  SELECT part_name,
         dateDiff('microsecond', minIf(event_time_microseconds, event_type = 'NewPart'),
                                 minIf(event_time_microseconds, event_type = 'DownloadPart')) / 1000 AS lag_ms
  FROM clusterAllReplicas('default', system.part_log)
  WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
    AND database = 'smt_lab' AND table = 'vis' AND event_type IN ('NewPart', 'DownloadPart')
  GROUP BY part_name
  HAVING countIf(event_type = 'NewPart') = 1 AND countIf(event_type = 'DownloadPart') = 1
)"

echo
echo "-- Gap the trials actually tested: INSERT finished → check query started (same connection, query_log)"
show "
WITH i AS (
  SELECT hostname, event_time_microseconds AS t FROM clusterAllReplicas('default', system.query_log)
  WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
    AND type = 'QueryFinish' AND log_comment = 'lab:vis-insert' AND is_initial_query),
c AS (
  SELECT hostname, query_start_time_microseconds AS t FROM clusterAllReplicas('default', system.query_log)
  WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
    AND type = 'QueryFinish' AND log_comment LIKE 'lab:vis-check%' AND is_initial_query)
SELECT count() AS trials,
       round(min(gap_ms), 1) AS min_ms, round(quantile(0.5)(gap_ms), 1) AS p50_ms, round(max(gap_ms), 1) AS max_ms
FROM (SELECT dateDiff('microsecond', i.t, c.t) / 1000 AS gap_ms
      FROM c ASOF JOIN i ON c.hostname = i.hostname AND c.t >= i.t)"

echo
echo "-- select_sequential_consistency = 1: what it costs on a plain SELECT (10 runs each)"
for ssc in 0 1; do
  for _ in $(seq 1 10); do
    ch --format Null -q "SELECT count() FROM smt_lab.vis SETTINGS select_sequential_consistency = $ssc, log_comment = 'lab:vis-ssc$ssc', use_query_cache = 0"
  done
done
ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'"
show "
SELECT log_comment, count() AS runs,
       round(avg(query_duration_ms), 1) AS avg_ms, max(query_duration_ms) AS max_ms,
       round(avg(ProfileEvents['ZooKeeperTransactions']), 1) AS keeper_requests_avg
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND type = 'QueryFinish' AND log_comment LIKE 'lab:vis-ssc%'
GROUP BY log_comment
ORDER BY log_comment"

echo
echo "-- SYSTEM SYNC REPLICA ... LIGHTWEIGHT: wait until this replica has the parts Keeper knows about (3 runs)"
for _ in 1 2 3; do
  ch -q "SYSTEM SYNC REPLICA smt_lab.vis LIGHTWEIGHT"
done
ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'"
show "
SELECT hostname AS replica, query_duration_ms, ProfileEvents['ZooKeeperTransactions'] AS keeper_requests
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND type = 'QueryFinish' AND query_kind = 'System' AND query ILIKE 'SYSTEM SYNC REPLICA smt_lab.vis%'
ORDER BY event_time_microseconds"
