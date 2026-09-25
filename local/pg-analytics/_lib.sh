#!/usr/bin/env bash
# Shared helpers for the numbered scripts. Everything runs from the lab dir.
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$LAB_DIR"
[ -f .env ] || cp .env.example .env
# shellcheck disable=SC1091
set -a; . ./.env; set +a

# run a python entry point inside the runner container (Docker API + service DNS)
runner() { docker compose run --rm -T runner python "$@"; }
