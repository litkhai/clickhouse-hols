#!/usr/bin/env bash
# cloud_run.sh - run this lab's small-data files (01-05, errors/01, 99) on a ClickHouse Cloud service.
#
#   ./cloud_run.sh [env file]     default: ~/.config/khai-harness/secrets/clickhouse-seoul.env
#
# The env file holds CH_HOST, CH_USER, CH_PASSWORD (never printed). The client runs from the Docker image
# below, so only Docker is needed. Each file runs in ONE client session (one connection, so one replica:
# an INSERT and the SELECT after it see the same replica). Statements that fail are logged and the file goes on
# (--ignore-error), so a setting Cloud refuses shows up as an error line instead of stopping the run.
# Output: results/cloud-<version>.txt, with the service hostname replaced by <service>. The lab database rmt_mv is dropped at the end (99-cleanup.sql).
# 06-scale.sql is not run here (16.2M rows; the correctness files are the point on Cloud).
set -euo pipefail
ENV_FILE=${1:-$HOME/.config/khai-harness/secrets/clickhouse-seoul.env}
IMG=clickhouse/clickhouse-server:26.10.3.7
cd "$(dirname "$0")"
set -a; . "$ENV_FILE"; set +a
: "${CH_HOST:?CH_HOST missing in $ENV_FILE}" "${CH_USER:?}" "${CH_PASSWORD:?}"

cli() {
  docker run --rm -i -e CH_HOST -e CH_USER -e CH_PASSWORD "$IMG" \
    bash -c 'exec clickhouse-client --host "$CH_HOST" --user "$CH_USER" --password "$CH_PASSWORD" --secure "$@"' _ "$@"
}

version=$(cli -q "SELECT version()")
out="results/cloud-$version.txt"
mkdir -p results
{
  echo "# ClickHouse Cloud run of workload/replacingmergetree-mv"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "version: $version"
  echo "client image: $IMG"
  cli -q "SELECT 'replicas', count() FROM clusterAllReplicas(default, system.one)" 2>&1 || true
  echo
  echo "## settings (system.settings / system.merge_tree_settings)"
  cli --format TSV -q "
    SELECT name, value, 'session' FROM system.settings
    WHERE name IN ('deduplicate_blocks_in_dependent_materialized_views', 'optimize_on_insert', 'insert_deduplicate',
                   'optimize_move_to_prewhere_if_final', 'max_threads')
    UNION ALL
    SELECT name, value, 'table' FROM system.merge_tree_settings
    WHERE name IN ('non_replicated_deduplication_window', 'replicated_deduplication_window',
                   'allow_experimental_replacing_merge_with_cleanup', 'min_age_to_force_merge_seconds')
    ORDER BY 3, 1" 2>&1 || true
  for f in 01-double-count.sql 02-late-and-ties.sql 03-group-change-delete.sql 04-blocks-and-retries.sql \
           05-strategies.sql errors/01-mv-final.sql; do
    echo
    echo "## $f"
    cli -n --echo --ignore-error --format TSV < "$f" 2>&1 || true
    if [ "$f" = 01-double-count.sql ]; then
      echo
      echo "## engine of rmt_mv.orders after 01"
      cli --format TSV -q "SELECT engine_full FROM system.tables WHERE database = 'rmt_mv' AND name = 'orders'" 2>&1 || true
    fi
  done
  echo
  echo "## 99-cleanup.sql"
  cli -n --echo --ignore-error < 99-cleanup.sql 2>&1 || true
} | sed -E 's/[A-Za-z0-9.-]+\.clickhouse\.cloud(:[0-9]+)?/<service>/g' > "$out"   # never write the service hostname
grep -c "Code: " "$out" | xargs -I{} echo "wrote $out ({} error lines; expected: errors/01 Code 397, plus any setting Cloud refuses)"
