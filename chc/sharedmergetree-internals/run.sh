#!/usr/bin/env bash
# Runs every NN-* step in order against a ClickHouse Cloud service and keeps
# a masked copy of each step's output in out/ (gitignored).
#   ./run.sh            all steps, 01 → 99 (99 drops the lab database)
#   ./run.sh 05 06      only the steps whose number is given
#   KEEP=1 ./run.sh     every step but 99, so the lab objects stay for screenshots
set -euo pipefail
# pipefail: a failing step stops the run even though its output goes through tee.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
mkdir -p "$LAB_DIR/out"

for f in "$LAB_DIR"/[0-9][0-9]-*; do
  step="$(basename "$f")"
  if [ $# -gt 0 ] && [[ ! " $* " == *" ${step:0:2} "* ]]; then continue; fi
  if [ $# -eq 0 ] && [ "${KEEP:-0}" = "1" ] && [ "${step:0:2}" = "99" ]; then continue; fi
  echo "=== $step"
  case "$step" in
    *.sql) run_sql_file "$f" 2>&1 | mask | tee "$LAB_DIR/out/$step.txt" ;;
    *.sh)  bash "$f" 2>&1 | mask | tee "$LAB_DIR/out/$step.txt" ;;
  esac
done
