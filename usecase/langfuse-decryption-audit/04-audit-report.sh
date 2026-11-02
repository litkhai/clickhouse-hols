#!/usr/bin/env bash
# 04-audit-report.sh [since] — run the reviewer's queries in 04-audit-report.sql as `auditor`.
# since: an ISO time (default: the start of today, UTC).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
SINCE="${1:-$(date -u +%Y-%m-%dT00:00:00Z)}"
n=0
sed -e 's/--.*$//' "$LAB_DIR/04-audit-report.sql" | tr '\n' ' ' | tr ';' '\n' | while IFS= read -r q; do
  [ -n "${q// /}" ] || continue
  n=$((n+1))
  title=$(grep -E '^-- [0-9]\.' "$LAB_DIR/04-audit-report.sql" | sed -n "${n}p" | sed 's/^-- //')
  echo "════ $title ════"
  curl -sS -m 60 -u "auditor:$AUDITOR_PASSWORD" --data-binary "$q" \
    "http://127.0.0.1:18123/?default_format=PrettyCompactMonoBlock&param_since=$(jq -rn --arg s "$SINCE" '$s|@uri')"
  echo
done
