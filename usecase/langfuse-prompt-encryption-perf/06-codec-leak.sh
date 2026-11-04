#!/usr/bin/env bash
# 06-codec-leak.sh — where does plaintext still reach disk when input/output use AES_256_GCM_SIV?
# Greps the part files (raw and decompressed) of bench.ev_codec (codec, Langfuse's text indexes kept) and bench.ev_local
# (ciphertext from the UDF, text indexes dropped) for a token that is in 1% of the prompts, and
# checks whether a search for it shows up in system.query_log.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
PASSES=0; FAILS=0
TOKEN=rx77refund
OUT="$RESULTS_DIR/leak.tsv"
printf 'table\tfile\tcontains_token\n' > "$OUT"

for t in ev_plain ev_codec ev_local; do
  say "$t: files that contain '$TOKEN'"
  ch -q "SELECT path FROM system.parts WHERE database = 'bench' AND table = '$t' AND active" | while read -r p; do
    # a file "contains" the token if it is there raw or after clickhouse-compressor --decompress
    # (column and index files are compressed; an encrypted column cannot be decompressed without the key)
    docker exec prompt-enc-ch-1 sh -c "cd '$p' && for f in *; do
        if grep -q -a '$TOKEN' \"\$f\" || clickhouse-compressor --decompress < \"\$f\" 2>/dev/null | grep -q -a '$TOKEN'; then
          echo \"\$f yes\"; else echo \"\$f no\"; fi; done"
  done | awk -v t="$t" '{k=$1; sub(/\.[0-9]+$/, "", k); seen[k]=seen[k] || ($2=="yes")} END {for (k in seen) printf "%s\t%s\t%s\n", t, k, (seen[k] ? "yes" : "no")}' \
    | sort | tee -a "$OUT" | awk -F'\t' '$3=="yes"'
done

hits() { awk -F'\t' -v t="$1" -v f="$2" '$1==t && $2==f {print $3}' "$OUT"; }
check "positive control: ev_plain input.bin decompresses to text with the token" yes "$(hits ev_plain input.bin)"
check "ev_codec input.bin holds no plaintext token" no "$(hits ev_codec input.bin)"
# The text index dictionary is front-coded (each token stores only what differs from the previous
# one), so the whole word is not in the file; its tail is: "rx77refund" follows a token starting with
# "r" and is stored as "x77refund". Grep the tail in the dictionary file of the largest part.
dict_has() { # dict_has <table> <string> → count of matching lines in the input text-index dictionary
  local p; p=$(ch -q "SELECT path FROM system.parts WHERE database = 'bench' AND table = '$1' AND active ORDER BY rows DESC LIMIT 1")
  docker exec prompt-enc-ch-1 sh -c "grep -c -a '$2' '$p/skp_idx_idx_fts_input_low.dct.idx' || true"
}
check "positive control: ev_plain text-index dictionary holds 'x77refund'" 1 "$(dict_has ev_plain x77refund)"
check "ev_codec text-index dictionary holds 'x77refund' in clear (codec does not cover indexes)" 1 "$(dict_has ev_codec x77refund)"
check "ev_codec and ev_plain dictionaries are byte-identical" 1 "$(
  a=$(ch -q "SELECT path FROM system.parts WHERE database = 'bench' AND table = 'ev_plain' AND active ORDER BY rows DESC LIMIT 1")
  b=$(ch -q "SELECT path FROM system.parts WHERE database = 'bench' AND table = 'ev_codec' AND active ORDER BY rows DESC LIMIT 1")
  docker exec prompt-enc-ch-1 sh -c "cmp -s '$a/skp_idx_idx_fts_input_low.dct.idx' '$b/skp_idx_idx_fts_input_low.dct.idx' && echo 1 || echo 0")"
check "ev_local (UDF ciphertext, no text index): no file holds the token" "" "$(awk -F'\t' '$1=="ev_local" && $3=="yes" {print $2}' "$OUT")"

say "query_log: a search for the token is logged in clear"
ch -q "SELECT count() FROM bench.ev_codec WHERE position(lower(input), '$TOKEN') > 0 FORMAT Null"
ch -q "SYSTEM FLUSH LOGS"
check "query text with the token in system.query_log" 1 "$(ch -q "SELECT count() > 0 FROM system.query_log WHERE query LIKE '%FROM bench.ev_codec WHERE position(lower(input), ''$TOKEN'')%'")"
echo; echo "06-codec-leak: $PASSES PASS, $FAILS FAIL"
