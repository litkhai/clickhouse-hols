#!/usr/bin/env bash
# The light run behind RESULTS.md, unattended (~20 min at SF10 after the build).
#   Load: hot months into heap, cold months written straight into Iceberg
#   (--bulk, one commit per table; no monthly tiering job), Phase 0 gate.
#   Bench: 9 queries covering L1-L5, dimensions in the lake (D1), warm only,
#   1 warm-up + 3 timed runs on A (correctness reference), B' (pg_duckdb main)
#   and C (pg_clickhouse). B (pg_duckdb 1.1.1) runs Q6 and C1 once to show the
#   month-pruning bug. The full design is the numbered scripts; see README.
# usage: ./run-all.sh [sf]   (default 10). Logs to results/run-all.log.
source "$(dirname "$0")/_lib.sh"
sf=${1:-10}
queries=q01,q06,c1,c2,q03,q05,q18,c5,c6
exec > >(tee -a results/run-all.log) 2>&1
echo "=== sf$sf light $(date -u +%FT%TZ)"
runner datagen/gen.py "$sf"
runner runner/setup.py all "$sf" --bulk
runner runner/verify.py "$sf"
runner runner/bench.py --sf "$sf" --paths A,B2,C --dims D1 --warm-only --iters 3 --queries "$queries"
runner runner/bench.py --sf "$sf" --paths B --dims D1 --warm-only --iters 1 --queries q06,c1
echo "=== done $(date -u +%FT%TZ)"
