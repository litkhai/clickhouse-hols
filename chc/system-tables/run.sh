#!/usr/bin/env bash
# Runs every NN-* step in order against a ClickHouse Cloud service and keeps
# a masked copy of each step's output in out/ (gitignored).
#   ./run.sh            all steps, 01 → 99 (99 drops the lab database)
#   ./run.sh 05 06      only the steps whose number is given
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
mkdir -p "$LAB_DIR/out"

for f in "$LAB_DIR"/[0-9][0-9]-*; do
  step="$(basename "$f")"
  if [ $# -gt 0 ] && [[ ! " $* " == *" ${step:0:2} "* ]]; then continue; fi
  echo "=== $step"
  case "$step" in
    *expected-error.sql)
      # Negative check: this step must fail on the server, and the failure
      # must be what the later steps look for in query_log and system.errors.
      if ch --echo --queries-file "$f" > "$LAB_DIR/out/$step.txt" 2>&1; then
        echo "FAIL: $step was expected to raise an error"; exit 1
      fi
      mask < "$LAB_DIR/out/$step.txt" | tee "$LAB_DIR/out/$step.txt.tmp"
      mv "$LAB_DIR/out/$step.txt.tmp" "$LAB_DIR/out/$step.txt" ;;
    *.sql) run_sql_file "$f" 2>&1 | mask | tee "$LAB_DIR/out/$step.txt" ;;
    *.sh)  bash "$f" 2>&1 | mask | tee "$LAB_DIR/out/$step.txt" ;;
  esac
done
