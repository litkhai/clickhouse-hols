#!/usr/bin/env bash
# 04-write-small.sh — W2: Langfuse-sized inserts (one trace = 4 observations per INSERT) at a fixed
# rate, per method. Encrypting "in ClickHouse on insert" means the writer inserts into a Null table
# and a materialized view writes the encrypted rows to the stored table, so that is what we build:
#
#   plain, codec          INSERT straight into a table with Langfuse's schema (codec: AES_256_GCM_SIV)
#   sql, local, kms_*     INSERT into bench.in_<m> (Null) → MV applies enc_<fn>() → bench.small_<m>
#
#   RATES="67 267" (traces/s; 67 ≈ 4,000 per minute)  SECONDS_PER_RUN=30
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
RATES="${RATES:-67 267}"
SECS="${SECONDS_PER_RUN:-30}"
METHODS="${METHODS:-plain codec sql local kms_batch kms_batch5 kms_row kms_row5}"
OUT="$RESULTS_DIR/w2-small.tsv"
PAYLOAD="$RESULTS_DIR/raw/payload.jsonl"; mkdir -p "$(dirname "$PAYLOAD")"

ddl() { # ddl <table> [codec] [drop-fts] — Langfuse's DDL renamed; drop-fts removes the text indexes on input/output
  local codec="${2:-ZSTD(3)}" drop="${3:-}"
  sed -e "s/default\.events_full/bench.$1/" \
      ${drop:+-e "/INDEX idx_fts_input_low/d" -e "/INDEX idx_fts_output_low/d"} \
      -e "s/\`input\` String CODEC(ZSTD(3))/\`input\` String CODEC($codec)/" \
      -e "s/\`output\` String CODEC(ZSTD(3))/\`output\` String CODEC($codec)/" \
      "$LAB_DIR/sql/events_full.langfuse-4.56.0.sql"
}
cpu() { docker exec "$1" cat /sys/fs/cgroup/cpu.stat | awk '/^usage_usec/ {print $2}'; }
fn_for() { case $1 in sql) echo enc_sql;; local) echo enc_local;; kms_batch) echo enc_kms_batch;;
  kms_batch5) echo enc_kms_batch_rtt5;; kms_row) echo enc_kms_row;; kms_row5) echo enc_kms_row_rtt5;; esac; }

if [ ! -s "$PAYLOAD" ]; then
  say "payload: 2,000 traces from bench.ev_plain as JSON arrays of their 4 rows"
  ch -q "SELECT * FROM bench.ev_plain WHERE trace_id IN (SELECT trace_id FROM bench.ev_plain WHERE parent_span_id = '' ORDER BY cityHash64(trace_id) LIMIT 2000) ORDER BY trace_id, span_id FORMAT JSONEachRow" \
    | python3 -c '
import json, sys, itertools
rows = (json.loads(l) for l in sys.stdin)
for _, g in itertools.groupby(rows, key=lambda r: r["trace_id"]):
    print(json.dumps(list(g), ensure_ascii=False))' > "$PAYLOAD"
fi
echo "  payload: $(wc -l < "$PAYLOAD") traces, $(du -h "$PAYLOAD" | cut -f1)"

[ -f "$OUT" ] || printf 'method\ttarget_tps\tachieved_tps\tinserts\terrors\tp50_ms\tp95_ms\tp99_ms\tmax_ms\tlate_p95_ms\tch_cpu_ms_per_trace\tkms_cpu_ms_per_trace\n' > "$OUT"
for m in $METHODS; do
  for r in $RATES; do
    ch -q "DROP VIEW IF EXISTS bench.mv_$m SYNC"; ch -q "DROP TABLE IF EXISTS bench.in_$m SYNC"
    ch -q "DROP TABLE IF EXISTS bench.small_$m SYNC"
    case $m in
      plain) ddl "small_$m" | ch --multiquery; target="small_$m" ;;
      codec) ddl "small_$m" "ZSTD(3), AES_256_GCM_SIV" | ch --multiquery; target="small_$m" ;;
      *)     ddl "small_$m" "ZSTD(3)" drop-fts | ch --multiquery
             ch -q "CREATE TABLE bench.in_$m AS bench.small_$m ENGINE = Null"
             f=$(fn_for "$m")
             ch -q "CREATE MATERIALIZED VIEW bench.mv_$m TO bench.small_$m AS SELECT * REPLACE ($f(input) AS input, $f(output) AS output) FROM bench.in_$m"
             target="in_$m" ;;
    esac
    c0=$(cpu prompt-enc-ch-1); b0=$(cpu prompt-enc-openbao-1)
    line=$(python3 "$LAB_DIR/bench/small_insert.py" "$target" "$r" "$SECS" "$PAYLOAD")
    c1=$(cpu prompt-enc-ch-1); b1=$(cpu prompt-enc-openbao-1)
    n=$(echo "$line" | cut -f3)
    printf '%s\t%s\t%s\t%s\n' "$m" "$line" \
      "$(python3 -c "print(f'{($c1-$c0)/1000/max($n,1):.1f}')")" "$(python3 -c "print(f'{($b1-$b0)/1000/max($n,1):.1f}')")" | tee -a "$OUT"
    stored=$(ch -q "SELECT count() FROM bench.small_$m")
    [ "$stored" = $((n * 4)) ] || echo "  note: $m stored $stored rows for $n inserts"
    sleep 20  # let merges of the small parts settle before the next run
  done
done
