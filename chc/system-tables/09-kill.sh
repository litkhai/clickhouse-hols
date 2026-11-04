#!/usr/bin/env bash
# 09 — KILL QUERY reaches only the replica its connection lands on.
# Each attempt starts a 60-second query, then sends a plain KILL QUERY on a new
# connection. If the KILL lands on the replica that runs the query, the query
# stops (a hit). If it lands on another replica, nothing happens (a miss) and
# KILL QUERY ON CLUSTER 'default' is needed. Attempts repeat until a miss.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
RUN="systables-lab-$(date +%s)"
running() { ch --format TSV -q "SELECT count() FROM clusterAllReplicas('default', system.processes) WHERE query_id = '$1'"; }

for attempt in 1 2 3 4 5 6; do
  QID="$RUN-$attempt"
  ch --query_id "$QID" --format Null -q "SELECT sleepEachRow(0.5) FROM numbers(120) SETTINGS max_block_size = 1, log_comment = 'lab:long'" >/dev/null 2>&1 &
  sleep 4
  ch --query_id "$QID-kill" --format Null -q "KILL QUERY WHERE query_id = '$QID' SYNC"
  sleep 1
  if [ "$(running "$QID")" = "0" ]; then
    echo "attempt $attempt: plain KILL stopped the query"
    wait; continue
  fi
  echo "attempt $attempt: plain KILL did not stop the query; sending KILL QUERY ON CLUSTER 'default'"
  ch --format Null -q "KILL QUERY ON CLUSTER 'default' WHERE query_id = '$QID' SYNC"
  sleep 1
  echo "still running on any replica: $(running "$QID")"
  wait; break
done

ch -q "SYSTEM FLUSH LOGS ON CLUSTER 'default'" >/dev/null
echo "-- each attempt from query_log: where the query ran, where its plain KILL ran"
show "
SELECT
    toUInt8(extract(query_id, '-([0-9]+)(-kill)?\$')) AS attempt,
    if(query_id LIKE '%-kill', 'plain KILL', 'long query') AS what,
    hostName() AS replica,
    type,
    errorCodeToName(exception_code) AS error
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND query_id LIKE '$RUN-%' AND type != 'QueryStart'
ORDER BY attempt, what"
