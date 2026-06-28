#!/usr/bin/env bash
# 07-benchmark.sh — wall-clock the point lookup across all 5 targets, N runs each.
# Uses the dockerized clickhouse-client with --time (prints elapsed seconds).
set -euo pipefail
cd "$(dirname "$0")"
. ./_env.sh; load_env

CID="${LOOKUP_CUSTOMER:-4242}"
RUNS="${1:-5}"

echo "▶ point lookup: customer_id = $CID   ($RUNS runs per table, results discarded)"
for t in engine_misaligned engine_aligned engine_default_aligned connect_misaligned connect_aligned; do
  echo "=== kpart.$t ==="
  for i in $(seq 1 "$RUNS"); do
    chc --time --query \
      "SELECT count(), avg(val) FROM kpart.$t WHERE customer_id = $CID FORMAT Null"
  done
done

cat <<EOF

Note / 참고:
  At these row counts on a laptop the fixed per-query overhead dominates, so the
  wall-clock gap is smaller than the parts/rows/marks gap from 06-compare.sql.
  read_rows / marks are the deterministic proof; latency widens as data and part
  counts grow. (로컬 규모에선 고정 오버헤드가 커서 시간 격차는 작다. read_rows·마크 수가
  결정적 증거이며, 데이터·part가 늘수록 지연 격차가 벌어진다.)
EOF
