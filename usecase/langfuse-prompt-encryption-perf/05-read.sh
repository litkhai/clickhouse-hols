#!/usr/bin/env bash
# 05-read.sh — R1–R5: Langfuse-shaped reads per method, with clickhouse-benchmark at several
# concurrency levels. Each run draws its queries at random from 100 variants (random trace or day).
#
#   detail  one trace's observations with full input/output            (trace page)
#   list    newest 50 observations of one day with 200-char previews    (observations table)
#           plain/codec read the preview table, as Langfuse reads events_core;
#           encrypted methods must decrypt events_full, the preview of a ciphertext is useless
#   search  count of one day's observations whose input contains a token (Langfuse's "matches":
#           position(lower(input), t) > 0 AND hasAllTokens(lower(input), tokens(t)) → text index)
#   export  every input/output of one day, decrypted                    (export, evaluation jobs)
#   agg     cost and latency by model over 7 days, no prompt column     (dashboard; control)
#
#   CONC="1 4 16"  TIME=20  (seconds per run)  METHODS="plain codec sql local kms_batch kms_batch5 kms_row kms_row5"
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
CONC="${CONC:-1 4 16}"
TIME="${TIME:-20}"
METHODS="${METHODS:-plain plain_noidx codec sql local kms_batch kms_batch5 kms_row kms_row5}"
OUT="$RESULTS_DIR/r-read.tsv"
QDIR="$RESULTS_DIR/raw/queries"; mkdir -p "$QDIR"

# preview table for the codec method (Langfuse's events_core would carry the same codec)
if [ "$(ch -q "EXISTS TABLE bench.core_codec")" = 0 ]; then
  sed -e "s/default\.events_full/bench.core_codec/" \
      -e "s/\`input\` String CODEC(ZSTD(3))/\`input\` String CODEC(ZSTD(3), AES_256_GCM_SIV)/" \
      -e "s/\`output\` String CODEC(ZSTD(3))/\`output\` String CODEC(ZSTD(3), AES_256_GCM_SIV)/" \
      "$LAB_DIR/sql/events_full.langfuse-4.56.0.sql" | ch --multiquery
  ch -q "INSERT INTO bench.core_codec SELECT * FROM bench.core_plain"
  ch -q "OPTIMIZE TABLE bench.core_codec FINAL"
fi

# method → table, preview table, decrypt function (empty = transparent)
spec() {
  case $1 in
    plain|plain_noidx) echo "ev_plain core_plain -" ;;
    codec)      echo "ev_codec core_codec -" ;;
    sql)        echo "ev_sql - dec_sql" ;;
    local)      echo "ev_local - dec_local" ;;
    kms_batch)  echo "ev_kms - dec_kms_batch" ;;
    kms_batch5) echo "ev_kms - dec_kms_batch_rtt5" ;;
    kms_row)    echo "ev_kms - dec_kms_row" ;;
    kms_row5)   echo "ev_kms - dec_kms_row_rtt5" ;;
  esac
}
# which queries each method runs (one-value-per-call KMS is far too slow for whole days)
queries_for() {
  case $1 in
    plain_noidx) echo "search" ;;
    kms_row|kms_row5) echo "detail list" ;;
    *) echo "detail list search export agg" ;;
  esac
}

TRACE_IDS=$(ch -q "SELECT trace_id FROM bench.ev_plain WHERE parent_span_id = '' ORDER BY cityHash64(trace_id) LIMIT 100")
DAYS="2026-11-01 2026-11-02 2026-11-03 2026-11-04 2026-11-05 2026-11-06 2026-11-07"
P="project_id = 'bench-project'"

make_queries() { # make_queries <method> <query> > file
  local m=$1 q=$2 t pv f; read -r t pv f <<<"$(spec "$m")"
  local IN=input OUT_=output
  [ "$f" != - ] && { IN="$f(input)"; OUT_="$f(output)"; }
  local i=0
  case $q in
    detail) for tid in $TRACE_IDS; do
        echo "SELECT span_id, type, start_time, $IN, $OUT_ FROM bench.$t WHERE $P AND trace_id = '$tid' FORMAT Null"; done ;;
    list|search|export) for k in $(seq 1 100); do
        d=$(echo $DAYS | tr ' ' '\n' | sed -n "$(( (k % 7) + 1 ))p")
        W="$P AND start_time >= '$d 00:00:00' AND start_time < toDateTime64('$d 00:00:00', 6) + INTERVAL 1 DAY"
        case $q in
          list) if [ "$pv" != - ]; then
                  echo "SELECT span_id, name, start_time, input, output FROM bench.$pv WHERE $W ORDER BY start_time DESC LIMIT 50 FORMAT Null"
                else
                  echo "SELECT span_id, name, start_time, leftUTF8($IN, 200), leftUTF8($OUT_, 200) FROM bench.$t WHERE $W ORDER BY start_time DESC LIMIT 50 FORMAT Null"
                fi ;;
          search) if [ "$m" = plain_noidx ]; then
                    echo "SELECT count() FROM bench.$t WHERE $W AND position(lower(input), 'rx77refund') > 0 FORMAT Null SETTINGS use_skip_indexes = 0"
                  elif [ "$f" = - ]; then
                    echo "SELECT count() FROM bench.$t WHERE $W AND position(lower(input), 'rx77refund') > 0 AND hasAllTokens(lower(input), ['rx77refund']) FORMAT Null"
                  else
                    echo "SELECT count() FROM bench.$t WHERE $W AND position(lower($IN), 'rx77refund') > 0 FORMAT Null"
                  fi ;;
          export) echo "SELECT span_id, $IN, $OUT_ FROM bench.$t WHERE $W FORMAT Null" ;;
        esac; done ;;
    agg) for k in $(seq 1 100); do
        echo "SELECT provided_model_name, count(), sum(calculated_total_cost), quantile(0.95)(dateDiff('millisecond', start_time, end_time)) FROM bench.$t WHERE $P AND type = 'GENERATION' AND start_time >= '2026-11-01' + INTERVAL $((k % 3)) DAY GROUP BY 1 FORMAT Null"; done ;;
  esac
}

[ -f "$OUT" ] || printf 'method\tquery\tconcurrency\tqueries\tqps\tp50_ms\tp95_ms\tp99_ms\terrors\n' > "$OUT"
for m in $METHODS; do
  for q in $(queries_for "$m"); do
    qf="$QDIR/$m-$q.sql"; make_queries "$m" "$q" > "$qf"
    for c in $CONC; do
      grep -q "^$m	$q	$c	" "$OUT" && continue   # already measured (re-runs resume)
      # Executable-UDF memory is outside ClickHouse's memory limit: local search at 16 got the whole
      # container OOM-killed (2026-11-04). Whole-day decrypts at 16 are not run for UDF/KMS methods.
      case "$m:$q:$c" in local:search:16|local:export:16|kms_*:search:16|kms_*:export:16|kms_batch5:export:4)
        printf '%s\t%s\t%s\t0\t0\t\t\t\tskipped\n' "$m" "$q" "$c" | tee -a "$OUT"; continue ;; esac
      # warm-up: one query (starts UDF processes, fills caches) — not counted
      head -n 1 "$qf" | ch >/dev/null
      docker exec -i prompt-enc-ch-1 clickhouse-benchmark --user bench --password "$CH_PASSWORD" \
        --concurrency "$c" --timelimit "$TIME" -r -d 0 --ignore-error < "$qf" 2>&1 | python3 -c '
import re, sys
m, q, c = sys.argv[1:4]
text = sys.stdin.read()
head = re.findall(r"queries: (\d+), (?:errors: (\d+), )?QPS: ([\d.]+)", text)
pct = dict(re.findall(r"^([\d.]+)%\s+([\d.]+) sec", text, re.M))
if not head:  # no query succeeded: the summary line is missing, count what was attempted
    tried = re.findall(r"Queries executed: (\d+)", text)
    if not tried:
        sys.stderr.write(text[-800:]); sys.exit(1)
    print(f"{m}\t{q}\t{c}\t0\t0\t\t\t\t{tried[-1]}"); sys.exit(0)
n, errs, qps = head[-1]
p50, p95, p99 = (float(pct.get(k, "nan")) * 1000 for k in ("50", "95", "99"))
errors = int(errs or 0)
print(f"{m}\t{q}\t{c}\t{n}\t{float(qps):.2f}\t{p50:.0f}\t{p95:.0f}\t{p99:.0f}\t{errors}")' "$m" "$q" "$c" | tee -a "$OUT"
    done
  done
done
