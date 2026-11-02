#!/usr/bin/env bash
# 99-down.sh [--purge] — stop this lab's containers. --purge also deletes the audit table and
# OpenBao's audit file (both volumes), .env and .state. Langfuse (langfuse-hols) is not touched.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
if [ "${1:-}" = --purge ]; then
  dc down -v --remove-orphans
  rm -f "$ENV_FILE" "$STATE"
  echo "✅ down, volumes, .env and .state removed"
else
  dc down --remove-orphans
  echo "✅ down (volumes kept: the audit table and OpenBao's audit file survive)"
fi
