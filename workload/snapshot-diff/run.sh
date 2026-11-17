#!/usr/bin/env bash
# run.sh - run this lab's SQL files on a ClickHouse Cloud service.
#
#   ./run.sh [env file]          default: ~/.config/khai-harness/secrets/clickhouse-seoul.env
#   KEEP=1 ./run.sh              keep the snapdiff database for screenshots (run 99-cleanup.sql afterwards)
#
# The env file holds CH_HOST, CH_USER, CH_PASSWORD (never printed). The client is `clickhouse client` when it
# is on PATH, otherwise the image below through Docker. Each file runs in ONE client session with --echo and
# --ignore-error, so an expected error (errors/01) is logged and the run goes on.
# Output: results/cloud-<version>.txt, with the service hostname replaced by <service>.
# scale.py (1M and 10M records) is separate.
set -euo pipefail
ENV_FILE=${1:-$HOME/.config/khai-harness/secrets/clickhouse-seoul.env}
IMG=clickhouse/clickhouse-server:26.10.3.7
cd "$(dirname "$0")"
set -a; . "$ENV_FILE"; set +a
: "${CH_HOST:?CH_HOST missing in $ENV_FILE}" "${CH_USER:?}" "${CH_PASSWORD:?}"

cli() {
  if command -v clickhouse >/dev/null 2>&1; then
    CLICKHOUSE_PASSWORD="$CH_PASSWORD" clickhouse client --host "$CH_HOST" --user "$CH_USER" --secure "$@"
  else
    docker run --rm -i -e CH_HOST -e CH_USER -e CH_PASSWORD "$IMG" \
      bash -c 'exec clickhouse-client --host "$CH_HOST" --user "$CH_USER" --password "$CH_PASSWORD" --secure "$@"' _ "$@"
  fi
}

version=$(cli -q "SELECT version()" 2>/dev/null)
out="results/cloud-$version.txt"
mkdir -p results
files=(00-setup.sql 01-boundary.sql 02-row-hash.sql 03-diff.sql 04-rmv.sql 05-insert-mv.sql 06-ttl.sql errors/01-append-incremental.sql)
[ "${KEEP:-0}" = 1 ] || files+=(99-cleanup.sql)
{
  echo "# ClickHouse Cloud run of workload/snapshot-diff"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "version: $version"
  cli -q "SELECT 'replicas', count() FROM clusterAllReplicas(default, system.one)" 2>&1 || true
  cli --format TSV -q "SELECT name, value FROM system.settings
    WHERE name IN ('max_threads', 'join_algorithm', 'parallel_view_processing', 'enable_analyzer') ORDER BY name" 2>&1 || true
  for f in "${files[@]}"; do
    echo
    echo "## $f"
    cli -n --echo --ignore-error --receive_timeout 600 --format PrettyCompactMonoBlock < "$f" 2>&1 || true
  done
} | grep -v 'azure_validate_etag' | sed -E 's/[A-Za-z0-9.-]+\.clickhouse\.cloud(:[0-9]+)?/<service>/g' > "$out"   # never write the service hostname
grep -c "Code: " "$out" | xargs -I{} echo "wrote $out ({} error lines; expected 1: errors/01, Code 62 on a build before 26.9)"
