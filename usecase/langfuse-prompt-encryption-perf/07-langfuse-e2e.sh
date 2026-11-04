#!/usr/bin/env bash
# 07-langfuse-e2e.sh — E1: the same OTLP load through a real Langfuse v4 (langfuse-hols stack, EE on),
# per variant, measuring what reaches ClickHouse and how late:
#
#   plain         Langfuse as shipped
#   codec         events_full / events_core input+output CODEC(ZSTD(3), AES_256_GCM_SIV)
#   cb_local      ingestion callback encrypts input/output, envelope key (no KMS call per request)
#   cb_kms_batch  callback asks OpenBao Transit to encrypt all values of a request in one call
#   cb_kms_row5   callback calls Transit once per value, +5 ms simulated round trip each
#
# The callback runs with FAIL_CLOSED=true and Langfuse's default 500 ms timeout: a request the
# callback cannot answer in time is dropped, not stored in clear.
#
#   RATE=67 (traces/s, 4 spans each)  SECONDS_PER_RUN=120  VARIANTS="plain codec cb_local cb_kms_batch cb_kms_row5"
# Restores the stack (OSS mode, original codecs, bench rows deleted) at the end: 07-langfuse-e2e.sh --restore-only
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
RATE="${RATE:-67}"
SECS="${SECONDS_PER_RUN:-120}"
VARIANTS="${VARIANTS:-plain codec cb_local cb_kms_batch cb_kms_row5}"
OUT="$RESULTS_DIR/e1-langfuse.tsv"
LFB="$LANGFUSE_HOLS_DIR/_base"
export PROMPT_ENC_LAB_DIR="$LAB_DIR"
PAYLOAD="$RESULTS_DIR/raw/payload.jsonl"
[ -s "$PAYLOAD" ] || { echo "✗ $PAYLOAD missing — run 04-write-small.sh first (it writes the payload)"; exit 1; }

lfc() { # lfc [overlay-file ...] -- <compose args>
  local files=(-f "$LFB/docker-compose.yml")
  while [ "$1" != -- ]; do files+=(-f "$1"); shift; done; shift
  docker compose -p langfuse-hols-v4 --project-directory "$LFB" --env-file "$LFB/v4/versions.env" \
    --env-file "$LFB/.env" --env-file "$ENV_FILE" "${files[@]}" "$@"
}
lch() { docker exec -i langfuse-hols-v4-clickhouse-1 clickhouse-client "$@"; }
cpu() { docker exec "$1" cat /sys/fs/cgroup/cpu.stat 2>/dev/null | awk '/^usage_usec/ {print $2}' || echo 0; }
wait_web() { for _ in $(seq 1 120); do curl -fsS http://localhost:3000/api/public/health >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }
set_codec() { # set_codec "<codec list>" — events_full and events_core input/output
  for t in events_full events_core; do
    lch -q "ALTER TABLE default.$t MODIFY COLUMN input String CODEC($1), MODIFY COLUMN output String CODEC($1)"
  done
}
restore() {
  say "restore: bench rows deleted, original codecs, parts rewritten, stack back to OSS mode"
  lch -q "DELETE FROM default.events_full WHERE has(metadata_names, 'bench_run')" || true
  lch -q "DELETE FROM default.events_core WHERE has(metadata_names, 'bench_run')" || true
  # events_core's input/output have no codec in Langfuse's schema; events_full's are ZSTD(3)
  lch -q "ALTER TABLE default.events_full MODIFY COLUMN input String CODEC(ZSTD(3)), MODIFY COLUMN output String CODEC(ZSTD(3))" || true
  lch -q "ALTER TABLE default.events_core MODIFY COLUMN input String CODEC(Default), MODIFY COLUMN output String CODEC(Default)" || true
  lch -q "OPTIMIZE TABLE default.events_full FINAL" || true
  lch -q "OPTIMIZE TABLE default.events_core FINAL" || true
  lfc -- up -d --remove-orphans
  wait_web && echo "  Langfuse is back in OSS mode"
}
[ "${1:-}" = --restore-only ] && { restore; exit 0; }

# project keys of the langfuse-hols stack (macOS bash 3.2 cannot source a process substitution)
env_val() { sed -n "s/^$1=//p" "$LFB/.env" | head -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/'; }
LANGFUSE_PUBLIC_KEY=$(env_val LANGFUSE_INIT_PROJECT_PUBLIC_KEY); LANGFUSE_SECRET_KEY=$(env_val LANGFUSE_INIT_PROJECT_SECRET_KEY)
export LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY
[ -n "$LANGFUSE_PUBLIC_KEY" ] && [ -n "$LANGFUSE_SECRET_KEY" ] || { echo "✗ project keys not found in $LFB/.env"; exit 1; }

[ -f "$OUT" ] || printf 'variant\trate_tps\tsent_traces\taccept_p50_ms\taccept_p95_ms\thttp_errors\texpected_rows\tarrived_rows\tencrypted_rows\tlag_p50_s\tlag_p95_s\tlag_p99_s\tlag_max_s\tdrain_after_send_s\tworker_cpu_s\tch_cpu_s\tcallback_cpu_s\n' > "$OUT"
for v in $VARIANTS; do
  say "variant $v"
  case $v in
    plain|codec) lfc "$LFB/docker-compose.ee.yml" "$LAB_DIR/docker-compose.langfuse.yml" -- up -d --remove-orphans ;;
    cb_*) ENC_MODE="${v#cb_}" ENC_TIMEOUT_MS=500 lfc "$LFB/docker-compose.ee.yml" "$LAB_DIR/docker-compose.langfuse.yml" \
            "$LAB_DIR/docker-compose.langfuse-callback.yml" -- up -d --remove-orphans ;;
  esac
  wait_web
  if [ "$v" = codec ]; then set_codec "ZSTD(3), AES_256_GCM_SIV"; else set_codec "ZSTD(3)"; fi
  sleep 10
  run="bench-$v-$(date +%s)"
  w0=$(cpu langfuse-hols-v4-langfuse-worker-1); c0=$(cpu langfuse-hols-v4-clickhouse-1); k0=$(cpu langfuse-hols-v4-enc-callback-1)
  load=$(python3 "$LAB_DIR/bench/otlp_load.py" "$run" "$RATE" "$SECS" "$PAYLOAD")
  sent_end=$(date -u +%s)
  echo "  load: $load"
  # wait until the row count stops growing (10 s unchanged) or 600 s
  prev=-1; same=0
  for _ in $(seq 1 300); do
    n=$(lch -q "SELECT count() FROM default.events_full WHERE has(metadata_values, '$run')")
    if [ "$n" = "$prev" ]; then same=$((same+1)); [ $same -ge 5 ] && break; else same=0; fi
    prev=$n; sleep 2
  done
  w1=$(cpu langfuse-hols-v4-langfuse-worker-1); c1=$(cpu langfuse-hols-v4-clickhouse-1); k1=$(cpu langfuse-hols-v4-enc-callback-1)
  sent=$(echo "$load" | cut -f3)
  stats=$(lch -q "
    SELECT count(), countIf(startsWith(input, 'v1:') OR startsWith(input, 'vault:v1:')),
      round(quantile(0.5)(lag), 2), round(quantile(0.95)(lag), 2), round(quantile(0.99)(lag), 2), round(max(lag), 2),
      round(greatest(0, toUnixTimestamp64Milli(max(created_at)) / 1000 - $sent_end), 1)
    FROM (SELECT input, created_at, (toUnixTimestamp64Milli(created_at) - toUnixTimestamp64Milli(start_time)) / 1000 AS lag
          FROM default.events_full WHERE has(metadata_values, '$run')) FORMAT TSV")
  read -r arrived enc l50 l95 l99 lmax drain <<<"$stats"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\n' "$v" "$RATE" "$sent" \
    "$(echo "$load" | cut -f5)" "$(echo "$load" | cut -f6)" "$(echo "$load" | cut -f4)" "$((sent * 4))" \
    "$arrived" "$enc" "$l50" "$l95" "$l99" "$lmax" "$drain" \
    "$(echo "($w1-$w0)/1000000" | bc -l)" "$(echo "($c1-$c0)/1000000" | bc -l)" "$(echo "(${k1:-0}-${k0:-0})/1000000" | bc -l)" | tee -a "$OUT"
done
restore
