#!/usr/bin/env bash
# 03-write-bulk.sh — W1: write the same 400k observations once per method (INSERT … SELECT from
# bench.ev_plain) and record, per method:
#   insert:  wall time, rows/s, plaintext MB/s, CPU seconds of the ClickHouse container (cgroup, so
#            executable-UDF child processes count) and of OpenBao, peak query memory
#   merges:  CPU seconds and peak memory of the background merges that follow, until none run
#   storage: input/output on disk and skip-index bytes after OPTIMIZE FINAL
# Every method starts only when no merge is running (merges of the previous table would otherwise
# land in its CPU numbers).
#
#   plain        copy into Langfuse's schema as is (text indexes on lower(input)/lower(output))
#   plain_nofts  same without those two text indexes — the baseline for the ciphertext methods
#   codec        input/output CODEC(ZSTD(3), AES_256_GCM_SIV), text indexes kept (transparent)
#   sql_fts      enc_sql() into Langfuse's schema unchanged (text indexes over base64 ciphertext)
#   sql          enc_sql()   built-in encrypt(), key inside the function definition
#   local        enc_local() executable UDF, data key unwrapped once from the KMS (envelope)
#   kms_batch    enc_kms_batch()       Transit encrypts, one call per ≤256 rows / 4 MiB
#   kms_batch5   enc_kms_batch_rtt5()  same + 5 ms simulated round trip per call
#   kms_row      enc_kms_row()         one Transit call per value (KMS_ROW_ROWS rows)
#   kms_row5     enc_kms_row_rtt5()    same + 5 ms per call (KMS_ROW5_ROWS rows)
# The tables the read benchmark needs stay (ev_plain is the source; ev_codec, ev_sql, ev_local,
# ev_kms); the others are dropped after they are measured, to keep the disk footprint down.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
OUT="$RESULTS_DIR/w1-bulk.tsv"
STORE="$RESULTS_DIR/w1-storage.tsv"
KMS_ROW_ROWS="${KMS_ROW_ROWS:-20000}"
KMS_ROW5_ROWS="${KMS_ROW5_ROWS:-4000}"
METHODS="${METHODS:-plain plain_nofts codec sql_fts sql local kms_batch kms_batch5 kms_row kms_row5}"
# max_block_size 2048: at 8192 rows × ~10 KB the SQL method's intermediate columns (SHA-256, encrypt,
# base64) on 8 threads went past an 8 GiB container. Same settings for every method.
SETTINGS="max_threads = 8, max_insert_threads = 4, max_block_size = 2048, min_insert_block_size_rows = 8192, min_insert_block_size_bytes = 0"

ddl() { # ddl <table> [codec] [drop-fts]
  local codec="${2:-ZSTD(3)}" drop="${3:-}"
  sed -e "s/default\.events_full/bench.$1/" \
      ${drop:+-e "/INDEX idx_fts_input_low/d" -e "/INDEX idx_fts_output_low/d"} \
      -e "s/\`input\` String CODEC(ZSTD(3))/\`input\` String CODEC($codec)/" \
      -e "s/\`output\` String CODEC(ZSTD(3))/\`output\` String CODEC($codec)/" \
      "$LAB_DIR/sql/events_full.langfuse-4.56.0.sql"
}
cpu() { docker exec "$1" cat /sys/fs/cgroup/cpu.stat | awk '/^usage_usec/ {print $2}'; }
now() { python3 -c 'import time; print(time.time())'; }
quiet() { # wait until no merge runs in bench (max 30 min)
  for _ in $(seq 1 900); do [ "$(ch -q "SELECT count() FROM system.merges WHERE database = 'bench'")" = 0 ] && return 0; sleep 2; done
  echo "  warning: merges still running after 30 min"
}

run() { # run <label> <table> <codec> <fn or -> <limit> [drop-fts] [keep]
  local label=$1 table=$2 codec=$3 fn=$4 limit=$5 drop=${6:-} keep=${7:-}
  case " $METHODS " in *" $label "*) ;; *) return 0 ;; esac
  say "$label → bench.$table"
  ch -q "DROP TABLE IF EXISTS bench.$table SYNC"
  ddl "$table" "$codec" "$drop" | ch --multiquery
  local fin=input fout=output
  if [ "$fn" != - ]; then fin="$fn(input)"; fout="$fn(output)"; fi
  local src="SELECT * REPLACE ($fin AS input, $fout AS output) FROM bench.ev_plain LIMIT $limit"
  local nbytes; nbytes=$(ch -q "SELECT sum(length(input) + length(output)) FROM (SELECT input, output FROM bench.ev_plain LIMIT $limit)")
  quiet
  local qid="w1-$label-$(date +%s)" c0 b0 t0 t1 c1 b1 t2 c2
  c0=$(cpu prompt-enc-ch-1); b0=$(cpu prompt-enc-openbao-1); t0=$(now)
  ch --query_id "$qid" -q "INSERT INTO bench.$table $src SETTINGS $SETTINGS"
  t1=$(now); c1=$(cpu prompt-enc-ch-1); b1=$(cpu prompt-enc-openbao-1)
  quiet
  t2=$(now); c2=$(cpu prompt-enc-ch-1)
  ch -q "SYSTEM FLUSH LOGS"
  local mem mmem
  mem=$(ch -q "SELECT round(memory_usage / 1048576) FROM system.query_log WHERE query_id = '$qid' AND type = 'QueryFinish'")
  mmem=$(ch -q "SELECT round(max(peak_memory_usage) / 1048576) FROM system.part_log WHERE database = 'bench' AND table = '$table' AND event_type = 'MergeParts'")
  python3 - "$label" "$limit" "$nbytes" "$t0" "$t1" "$t2" "$c0" "$c1" "$c2" "$b0" "$b1" "$mem" "${mmem:-0}" <<'PY' | tee -a "$OUT"
import sys
label, rows, nbytes = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
t0, t1, t2, c0, c1, c2, b0, b1, mem, mmem = map(float, sys.argv[4:])
w = t1 - t0
print(f"{label}\t{rows}\t{w:.1f}\t{rows / w:.0f}\t{nbytes / w / 1e6:.1f}\t{(c1 - c0) / 1e6:.1f}\t{(c1 - c0) / rows:.0f}"
      f"\t{(b1 - b0) / 1e6:.1f}\t{mem:.0f}\t{t2 - t1:.0f}\t{(c2 - c1) / 1e6:.1f}\t{mmem:.0f}")
PY
  ch -q "OPTIMIZE TABLE bench.$table FINAL"
  ch -q "
    SELECT '$label', (SELECT sum(rows) FROM system.parts WHERE database = 'bench' AND table = '$table' AND active),
      round(sumIf(column_data_compressed_bytes, column = 'input') / 1048576),
      round(sumIf(column_data_compressed_bytes, column = 'output') / 1048576),
      round(sum(column_data_compressed_bytes) / 1048576),
      (SELECT round(sum(secondary_indices_compressed_bytes) / 1048576) FROM system.parts WHERE database = 'bench' AND table = '$table' AND active)
    FROM system.parts_columns WHERE database = 'bench' AND table = '$table' AND active FORMAT TSV" | tee -a "$STORE"
  [ -n "$keep" ] || ch -q "DROP TABLE bench.$table SYNC"
}

N=$(ch -q "SELECT count() FROM bench.ev_plain")
[ -f "$OUT" ] || printf 'method\trows\tinsert_s\trows_per_s\tplain_MB_per_s\tinsert_cpu_s\tinsert_cpu_us_per_row\tkms_cpu_s\tinsert_peak_MiB\tmerge_s\tmerge_cpu_s\tmerge_peak_MiB\n' > "$OUT"
[ -f "$STORE" ] || printf 'method\trows\tinput_MiB\toutput_MiB\tall_columns_MiB\tskip_indexes_MiB\n' > "$STORE"
#   label        table        codec                      function             rows             drop-fts  keep
run plain       ev_plain2    "ZSTD(3)"                   -                    "$N"
run plain_nofts ev_plain_nf  "ZSTD(3)"                   -                    "$N"             drop-fts
run codec       ev_codec     "ZSTD(3), AES_256_GCM_SIV"  -                    "$N"             ""        keep
run sql_fts     ev_sql_fts   "ZSTD(3)"                   enc_sql              "$N"
run sql         ev_sql       "ZSTD(3)"                   enc_sql              "$N"             drop-fts  keep
run local       ev_local     "ZSTD(3)"                   enc_local            "$N"             drop-fts  keep
run kms_batch   ev_kms       "ZSTD(3)"                   enc_kms_batch        "$N"             drop-fts  keep
run kms_batch5  ev_kms_b5    "ZSTD(3)"                   enc_kms_batch_rtt5   "$N"             drop-fts
run kms_row     ev_kms_row   "ZSTD(3)"                   enc_kms_row          "$KMS_ROW_ROWS"  drop-fts
run kms_row5    ev_kms_row5  "ZSTD(3)"                   enc_kms_row_rtt5     "$KMS_ROW5_ROWS" drop-fts
