#!/usr/bin/env bash
# 04 — Who runs a merge? 20 small INSERTs make 20 parts; background merges combine them.
# part_log on every replica then shows where each merged part was made and who only loaded it.
#   INSERTS=20 (default), WAIT_S=90: how long to wait for the parts to settle
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
# This step reads only log rows written after it started, so re-running it does not mix runs.
T0="$(ch -q "SELECT now64(6)")"
INSERTS="${INSERTS:-20}"; WAIT_S="${WAIT_S:-90}"

ch -q "CREATE TABLE IF NOT EXISTS smt_lab.m (id UInt64, v String) ENGINE = MergeTree ORDER BY id"
ch -q "TRUNCATE TABLE smt_lab.m"
for i in $(seq 1 "$INSERTS"); do
  ch -q "INSERT INTO smt_lab.m SETTINGS log_comment = 'lab:merge-insert' SELECT number + $i * 100000, toString(number) FROM numbers(50000)" < /dev/null
done
echo "$INSERTS inserts of 50,000 rows done; waiting for merges (up to ${WAIT_S}s)"

prev=-1; same=0
for _ in $(seq 1 "$WAIT_S"); do
  n="$(ch -q "SELECT count() FROM system.parts WHERE database = 'smt_lab' AND table = 'm' AND active")"
  if [ "$n" = "$prev" ]; then same=$((same + 1)); else same=0; prev="$n"; fi
  if [ "$same" -ge 10 ]; then break; fi   # unchanged for 10 s
  sleep 1
done
echo "active parts now: $prev"
ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'"
echo

echo "-- part_log events per replica"
show "
SELECT hostName() AS replica, event_type, count() AS events, sum(rows) AS rows,
       formatReadableSize(sum(ProfileEvents['WriteBufferFromS3Bytes'])) AS s3_written,
       formatReadableSize(sum(ProfileEvents['ReadBufferFromS3Bytes'])) AS s3_read
FROM clusterAllReplicas('default', system.part_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND database = 'smt_lab' AND table = 'm'
GROUP BY replica, event_type
ORDER BY replica, event_type"

echo
echo "-- Each merged part: how many replicas ran the merge, how many only loaded the result"
show "
SELECT part_name, any(rows) AS rows, length(anyIf(merged_from, event_type = 'MergeParts')) AS from_parts,
       groupArrayIf(hostname, event_type = 'MergeParts') AS merged_on,
       countIf(event_type = 'MergeParts') AS merges,
       countIf(event_type = 'DownloadPart') AS loaded_elsewhere
FROM clusterAllReplicas('default', system.part_log)
WHERE event_date = today() AND event_time_microseconds >= toDateTime64('$T0', 6)
  AND database = 'smt_lab' AND table = 'm' AND event_type IN ('MergeParts', 'DownloadPart')
GROUP BY part_name
HAVING merges > 0
ORDER BY min(event_time_microseconds)"

echo
echo "-- Which replica coordinates merges for this table, as each replica sees it"
show "
SELECT hostName() AS replica, merge_coordinator_replica, is_leader
FROM clusterAllReplicas('default', system.replicas)
WHERE database = 'smt_lab' AND table = 'm'
ORDER BY replica"

echo
echo "-- Merges are not queued per replica, as they are in ReplicatedMergeTree"
show "
SELECT hostName() AS replica, queue_size, merges_in_queue
FROM clusterAllReplicas('default', system.replicas)
WHERE database = 'smt_lab' AND table = 'm'
ORDER BY replica"
