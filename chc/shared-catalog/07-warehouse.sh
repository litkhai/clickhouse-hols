#!/usr/bin/env bash
# 07 — A warehouse with an idle service: do CREATE / RENAME / DROP DATABASE wait
# for it? The Warehouses docs still warn they "could be blocked by idled/stopped
# services". Does not wake the idle service (nothing here connects to it).
# Optional: CHC_KEY, CHC_SECRET (Cloud API key) to print every service's state
# before and after; read-only.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
set -e
states() {
  [ -n "${CHC_KEY:-}" ] || { echo "(CHC_KEY not set: service states skipped)"; return; }
  local org; org="$(curl -s -u "$CHC_KEY:$CHC_SECRET" https://api.clickhouse.cloud/v1/organizations | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"][0]["id"])')"
  curl -s -u "$CHC_KEY:$CHC_SECRET" "https://api.clickhouse.cloud/v1/organizations/$org/services" | python3 -c '
import sys, json
for s in json.load(sys.stdin)["result"]:
    print("service %-12s state=%-8s primary=%-5s replicas=%s readonly=%s" % (s["name"][:12], s["state"], s.get("isPrimary"), s.get("numReplicas"), s.get("isReadonly")))'
}
echo "## services in the warehouse, before"; states
show "SELECT cluster, host_name, is_active FROM system.clusters WHERE cluster = 'all_groups.default' ORDER BY host_name"
S0="$(ch -q "SELECT now64(6)" 2>/dev/null | grep -v '^Unknown')"
timed() { local t0 t1; t0=$(python3 -c 'import time; print(time.time())'); try "$@"; t1=$(python3 -c 'import time; print(time.time())'); python3 -c "print('   wall %.2f s' % ($t1 - $t0))"; }
echo "## default settings (output mode none_only_active, timeout 180)"
timed wh_create_db  "CREATE DATABASE sc_wh"
timed wh_create_t   "CREATE TABLE sc_wh.t (n UInt64) ENGINE = MergeTree ORDER BY n"
timed wh_rename_db  "RENAME DATABASE sc_wh TO sc_wh2"
timed wh_drop_db    "DROP DATABASE sc_wh2"
echo "## output mode throw: wait for every replica, active or not (timeout 20 s)"
timed wh_create_db_throw "CREATE DATABASE sc_wh3" --distributed_ddl_output_mode=throw --distributed_ddl_task_timeout=20
timed wh_drop_db_throw   "DROP DATABASE sc_wh3" --distributed_ddl_output_mode=throw --distributed_ddl_task_timeout=20
echo "## timeout 0: do not wait at all"
timed wh_create_db_t0 "CREATE DATABASE sc_wh4" --distributed_ddl_task_timeout=0
timed wh_drop_db_t0   "DROP DATABASE sc_wh4" --distributed_ddl_task_timeout=0
sleep 2; flush_logs
echo "## what the executing replica waited for"
show "SELECT hostName() AS replica, formatDateTime(event_time_microseconds, '%H:%i:%S.%f') AS at, substring(replaceRegexpAll(message, 'c-[a-z]+-[a-z]{2}-[0-9]+-server-', ''), 1, 200) AS message FROM clusterAllReplicas('default', system.text_log) WHERE event_time_microseconds >= '$S0' AND logger_name = 'SharedDatabaseCatalog' AND (message LIKE 'Waiting for replicas%' OR message ILIKE '%inactive%' OR message ILIKE '%timeout%' OR message LIKE '%sc_wh%') AND message NOT LIKE 'Applying changes%' ORDER BY event_time_microseconds LIMIT 30"
show "SELECT extract(log_comment, ':(wh_.*)') AS ddl, max(query_duration_ms) AS server_ms, max(exception_code) AS exception_code FROM clusterAllReplicas('default', system.query_log) WHERE event_time_microseconds >= '$S0' AND type != 'QueryStart' AND log_comment LIKE '$LAB_TAG:wh_%' GROUP BY ddl ORDER BY min(event_time_microseconds)" || true
echo "## services in the warehouse, after"; states
