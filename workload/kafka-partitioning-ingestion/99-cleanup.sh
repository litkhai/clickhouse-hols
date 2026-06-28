#!/usr/bin/env bash
# 99-cleanup.sh — tear the lab down. Pass --hard to also delete container volumes.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Stopping and removing containers…"
if [[ "${1:-}" == "--hard" ]]; then
  docker compose down -v --remove-orphans
  echo "✅ Containers + volumes removed."
else
  docker compose down --remove-orphans
  echo "✅ Containers removed (volumes kept; use --hard to wipe everything)."
fi
