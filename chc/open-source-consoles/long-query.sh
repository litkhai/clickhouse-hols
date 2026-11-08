#!/usr/bin/env bash
# A query that runs for about 14 minutes, for the running-queries and kill scenario.
# Its query_id starts with console-long- so it is easy to find in a tool.
#   ./long-query.sh            (uses CH_HOST / CH_USER / CH_PASSWORD from the environment or .env)
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$LAB_DIR/.env" ]; then set -a; . "$LAB_DIR/.env"; set +a; fi
: "${CH_HOST:?set CH_HOST}" "${CH_PASSWORD:?set CH_PASSWORD}"
qid="console-long-$(date +%H%M%S)"
echo "query_id $qid — kill it from a tool; the client then prints Code: 394 QUERY_WAS_CANCELLED"
clickhouse client --host "$CH_HOST" --port 9440 --secure --user "${CH_USER:-default}" --password "$CH_PASSWORD" \
  --query_id "$qid" --max_execution_time 900 \
  --query "SELECT sleepEachRow(0.5), number FROM numbers(1700)
           SETTINGS max_block_size = 1, function_sleep_max_microseconds_per_block = 0 FORMAT Null"
