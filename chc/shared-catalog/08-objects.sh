#!/usr/bin/env bash
# 08 — Objects whose definition is in the catalog but whose work is per replica:
# a dictionary (who loads it?) and a refreshable materialized view (who runs
# the refresh, and what does a refresh do to the catalog?).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
expect_ok src "CREATE TABLE sc_lab.dict_src (k UInt64, v String) ENGINE = MergeTree ORDER BY k"
expect_ok src_fill "INSERT INTO sc_lab.dict_src SELECT number, toString(number) FROM numbers(1000)"
echo "## dictionary"
try dict "CREATE DICTIONARY sc_lab.dict (k UInt64, v String) PRIMARY KEY k SOURCE(CLICKHOUSE(DB 'sc_lab' TABLE 'dict_src')) LAYOUT(HASHED()) LIFETIME(300)"
show "SELECT hostName() AS replica, name, status, element_count, loading_start_time FROM clusterAllReplicas('default', system.dictionaries) WHERE database = 'sc_lab' ORDER BY replica"
try dict_get "SELECT hostName() AS used_on, dictGet('sc_lab.dict', 'v', toUInt64(42)) AS v"
show "SELECT hostName() AS replica, name, status, element_count, loading_start_time FROM clusterAllReplicas('default', system.dictionaries) WHERE database = 'sc_lab' ORDER BY replica"
echo "## refreshable materialized view, every 10 s"
S0="$(ch -q "SELECT now64(6)" 2>/dev/null | grep -v '^Unknown')"
expect_ok rmv "CREATE MATERIALIZED VIEW sc_lab.rmv REFRESH EVERY 10 SECOND ENGINE = MergeTree ORDER BY k AS SELECT k % 10 AS k, count() AS c, now() AS at FROM sc_lab.dict_src GROUP BY k"
sleep 45
show "SELECT hostName() AS replica, status, last_success_time, last_refresh_replica, next_refresh_time, exception FROM clusterAllReplicas('default', system.view_refreshes) WHERE database = 'sc_lab' AND view = 'rmv' ORDER BY replica"
flush_logs
echo "-- refresh INSERTs per replica (query_log)"
show "SELECT hostName() AS replica, count() AS refresh_inserts FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$S0' AND type = 'QueryFinish' AND query_kind = 'Insert' AND query LIKE '%sc_lab%' AND query LIKE '%.tmp.inner_id.%' GROUP BY replica ORDER BY replica"
echo "-- what each refresh did to the catalog (stage changes logged for sc_lab objects, both replicas)"
show "SELECT replaceRegexpAll(message, '[0-9a-f-]{36}', '<uuid>') AS change, count() AS n FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$S0' AND logger_name = 'SharedDatabaseCatalog' AND (message LIKE '%sc_lab.%' OR message LIKE 'Applying changes%') AND (message LIKE '%.tmp.inner%' OR message LIKE '%rmv%' OR message LIKE 'Applying changes%' ) GROUP BY change ORDER BY n DESC LIMIT 12"
show "SELECT hostName() AS replica, formatDateTime(event_time_microseconds, '%H:%i:%S.%f') AS at, substring(message, 1, 170) AS message FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$S0' AND logger_name = 'SharedDatabaseCatalog' AND message LIKE '%sc_lab%' AND message LIKE '%tmp%' ORDER BY event_time_microseconds LIMIT 12"
try rmv_stop "SYSTEM STOP VIEW sc_lab.rmv"
