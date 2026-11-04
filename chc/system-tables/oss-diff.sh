#!/usr/bin/env bash
# Lists the system tables a Cloud service has and an OSS server of the same
# release does not. Needs Docker and the same connection as run.sh.
#   ./oss-diff.sh 26.8
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
TAG="${1:-26.8}"; NAME="systables-oss-diff"; PORT=18124
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "$PORT:8123" -e CLICKHOUSE_SKIP_USER_SETUP=1 "clickhouse/clickhouse-server:$TAG" >/dev/null
trap 'docker rm -f "$NAME" >/dev/null' EXIT
for _ in $(seq 1 30); do curl -sf "localhost:$PORT/ping" >/dev/null && break; sleep 1; done
oss() { curl -sf "localhost:$PORT/" --data-binary "$1"; }
oss "SELECT 1" >/dev/null; oss "SYSTEM FLUSH LOGS"   # log tables appear on their first flush
LIST="SELECT DISTINCT replaceRegexpOne(name, '_[0-9]+\$', '') FROM system.tables WHERE database = 'system' ORDER BY 1 FORMAT TSV"
TMP="$(mktemp -d)"
oss "$LIST" > "$TMP/oss"; ch -q "$LIST" | mask > "$TMP/cloud"
echo "OSS $(oss 'SELECT version()'): $(wc -l < "$TMP/oss" | tr -d " ") tables · Cloud $(ch -q 'SELECT version()'): $(wc -l < "$TMP/cloud" | tr -d " ") base names"
echo "-- only in Cloud"; comm -13 "$TMP/oss" "$TMP/cloud"
echo "-- only in OSS";   comm -23 "$TMP/oss" "$TMP/cloud"
rm -rf "$TMP"

SETTINGS_Q="SELECT name, value FROM system.settings WHERE name IN ('log_queries', 'log_queries_probability', 'log_processors_profiles', 'log_query_threads', 'log_query_views', 'query_profiler_real_time_period_ns', 'query_profiler_cpu_time_period_ns', 'opentelemetry_start_trace_probability', 'enable_blob_storage_log') ORDER BY name"
echo "-- logging settings: OSS value | Cloud value"
join -t $'\t' <(oss "$SETTINGS_Q FORMAT TSV") <(ch --format TSV -q "$SETTINGS_Q")
echo "-- built-in dashboards: OSS"
oss "SELECT dashboard, count() AS charts FROM system.dashboards GROUP BY dashboard ORDER BY dashboard FORMAT PrettyCompactMonoBlock"
