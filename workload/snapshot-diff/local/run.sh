#!/usr/bin/env bash
# local/run.sh - REFRESH ... APPEND INCREMENTAL (26.9+) on a local server: 00-setup.sql, then local/26.9-append-incremental.sql.
#
#   local/run.sh [port]      default 9000; any 26.9 or later server reachable as localhost:<port>
#
# Output: results/local-<version>.txt. Expected: Code 36 for the JOIN form, and every record 'new' for the GROUP BY form.
set -euo pipefail
PORT=${1:-9000}
cd "$(dirname "$0")/.."
cli() { clickhouse client --port "$PORT" "$@"; }
version=$(cli -q "SELECT version()")
out="results/local-$version.txt"
{
  echo "# local run of workload/snapshot-diff/local/26.9-append-incremental.sql"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "version: $version"
  cli -n --ignore-error < 00-setup.sql 2>&1
  cli -n --echo --ignore-error --format PrettyCompactMonoBlock < local/26.9-append-incremental.sql 2>&1
  cli -q "DROP DATABASE snapdiff SYNC" 2>&1
} | sed -E '/^[0-9]+\. (0x|DB::|Poco|std::|void|bool)/d' > "$out"
echo "wrote $out"
