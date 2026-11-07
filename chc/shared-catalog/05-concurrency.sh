#!/usr/bin/env bash
# 05 — Concurrent DDL: K connections at once, all on the SAME table vs each on
# its OWN table. Objects carry their own version; does a same-object race fail,
# retry, or serialise, and what does it cost?
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
K="${CONC:-8}"
expect_ok mk_same "CREATE TABLE sc_lab.cc_same (n UInt64) ENGINE = MergeTree ORDER BY n"
for i in $(seq 1 "$K"); do ch -q "CREATE TABLE sc_lab.cc_own$i (n UInt64) ENGINE = MergeTree ORDER BY n" 2>/dev/null; done
START="$(ch -q "SELECT now64(6)" 2>/dev/null | grep -v '^Unknown')"
race() { # race MODE: K parallel ALTERs, print each connection's outcome
  local mode="$1" i t
  for i in $(seq 1 "$K"); do
    if [ "$mode" = same ]; then t="sc_lab.cc_same"; else t="sc_lab.cc_own$i"; fi
    ( out="$(ch --log_comment="$LAB_TAG:conc:$mode" -q "ALTER TABLE $t ADD COLUMN c_$mode$i UInt8" 2>&1)" && echo "$mode $i OK" || echo "$mode $i $(printf '%s' "$out" | grep -oE 'Code: [0-9]+|\([A-Z_]+\)' | tr '\n' ' ')" ) &
  done
  wait
}
# query_log has two rows per ALTER: the inner one the catalog rewrites, "(ADD COLUMN ...)", is left out
echo "## $K parallel ALTER ADD COLUMN on one table"; race same | sort -k2n
show "SELECT any(substring(exception, 1, 300)) AS message FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$START' AND exception_code = 517 AND log_comment = '$LAB_TAG:conc:same'" || true
echo "## $K parallel ALTER ADD COLUMN, one table each"; race own | sort -k2n
sleep 2; flush_logs
show "SELECT extract(log_comment, 'conc:(.*)') AS mode, countIf(type = 'QueryFinish') AS ok, countIf(type != 'QueryFinish') AS failed, groupUniqArrayIf(exception_code, type != 'QueryFinish') AS codes, quantile(0.5)(query_duration_ms) AS p50_ms, max(query_duration_ms) AS max_ms, groupUniqArray(hostName()) AS replicas FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$START' AND type != 'QueryStart' AND log_comment LIKE '$LAB_TAG:conc:%' AND query NOT LIKE '%(ADD COLUMN%' GROUP BY mode ORDER BY mode"
show "SELECT hostName() AS replica, groupArray(name) AS columns FROM clusterAllReplicas('default', system.columns) WHERE database = 'sc_lab' AND table = 'cc_same' GROUP BY replica ORDER BY replica"
echo "## what the catalog logged while racing (shapes, both replicas)"
show "SELECT level, count() AS n, any(substring(message, 1, 170)) AS example FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$START' AND (logger_name = 'SharedDatabaseCatalog' OR logger_name LIKE '%cc_same%') AND (message ILIKE '%retry%' OR message ILIKE '%conflict%' OR message ILIKE '%changed%' OR message ILIKE '%version mismatch%' OR message ILIKE '%BADVERSION%' OR message ILIKE '%lock%' OR level IN ('Warning', 'Error')) GROUP BY level, replaceRegexpAll(message, '[0-9a-f-]{36}|[0-9.]+|c_[a-z]+[0-9]+', 'N') ORDER BY n DESC LIMIT 15"
