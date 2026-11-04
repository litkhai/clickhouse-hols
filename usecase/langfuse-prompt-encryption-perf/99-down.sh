#!/usr/bin/env bash
# 99-down.sh [--purge] — stop the bench stack. --purge also deletes its ClickHouse volume, .env,
# .secrets and results/raw. The Langfuse stack is not touched (07-langfuse-e2e.sh restores it itself;
# `07-langfuse-e2e.sh --restore-only` does it again if a run was interrupted).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
[ -f "$ENV_FILE" ] || { echo "nothing to stop (.env missing)"; exit 0; }
load_lab_env
if [ "${1:-}" = --purge ]; then
  dc down -v --remove-orphans
  rm -rf "$ENV_FILE" "$SECRETS_DIR" "$RESULTS_DIR/raw"
  echo "purged"
else
  dc down --remove-orphans
fi
