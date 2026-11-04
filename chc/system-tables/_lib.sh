#!/usr/bin/env bash
# Shared by run.sh and the NN-*.sh steps: connection and output masking.
# Connection comes from the environment or from .env next to this file (gitignored):
#   CH_HOST, CH_USER, CH_PASSWORD, optional CH_PORT (default 9440).
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$LAB_DIR/.env" ]; then set -a; . "$LAB_DIR/.env"; set +a; fi
: "${CH_HOST:?set CH_HOST (the service hostname, without https://)}"
: "${CH_USER:=default}"
: "${CH_PASSWORD:?set CH_PASSWORD}"
: "${CH_PORT:=9440}"
read -r -a CH_CLIENT <<< "${CH_CLIENT:-clickhouse client}"

# One connection per call. A Cloud service has several replicas behind a load
# balancer, so two calls can land on different replicas (02-routing.sh shows it).
# skip_unavailable_shards: clusterAllReplicas() skips a replica that is being added or removed.
ch() {
  "${CH_CLIENT[@]}" --host "$CH_HOST" --port "$CH_PORT" --secure \
    --user "$CH_USER" --password "$CH_PASSWORD" \
    --skip_unavailable_shards=1 "$@" 2> >(grep -v "^Unknown settings: " >&2)
}

# Captures are shared, so service-specific names are masked unless MASK=0:
# pod names keep only their random suffix (2rdd723-0), and the bucket, the
# service namespace, the endpoint and e-mail addresses are replaced.
mask() {
  if [ "${MASK:-1}" = "0" ]; then cat; return; fi
  sed -E \
    -e '/^Unknown settings: /d' \
    -e 's/\.c-[a-z0-9-]+-server-headless\.ns-[a-z0-9-]+\.svc\.cluster\.local//g' \
    -e 's/c-[a-z0-9-]+-server-([a-z0-9]{7}-[0-9]+)/\1/g' \
    -e 's/ch-s3-[0-9a-f-]{36}/ch-s3-<bucket>/g' \
    -e 's/system_tables_tracking_[a-z0-9_]+/system_tables_tracking_<svc>/g' \
    -e 's/[a-z0-9]+\.[a-z0-9-]+\.[a-z]+\.clickhouse\.cloud/<service>.clickhouse.cloud/g' \
    -e 's/clickpipe:[0-9a-f-]{36}/clickpipe:<id>/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    -e 's/__tmp_internal_[0-9]+/__tmp_internal_<n>/g'
}

# show "SQL": run one query, mask the result, then draw the table locally so the
# columns still line up after masking. Needs the single `clickhouse` binary
# (clickhouse local); without it the masked TSV is printed as is.
render() {
  local fmt="$1"
  if command -v clickhouse >/dev/null 2>&1; then
    mask | clickhouse local --input-format TSVWithNamesAndTypes --output-format "$fmt" \
      --output_format_pretty_row_numbers=0 --output_format_pretty_single_large_number_tip_threshold=0 -q "SELECT * FROM table"
  else
    mask
  fi
}
show() {
  local q="$1" fmt="PrettyCompactMonoBlock" out
  if [[ "$q" == *"FORMAT Vertical"* ]]; then fmt="Vertical"; q="${q/FORMAT Vertical/}"; fi
  out="$(ch --format TSVWithNamesAndTypes -q "$q")" || return 1
  if [ -n "$out" ]; then printf '%s\n' "$out" | render "$fmt"; fi
}

# run_sql_file FILE: print each statement (with the comments above it), then its result
run_sql_file() {
  local f="$1" tmp s body
  tmp="$(mktemp -d)"
  awk -v d="$tmp" '{ buf = buf $0 "\n" } /;[[:space:]]*$/ { n++; out = sprintf("%s/%03d.sql", d, n); printf "%s", buf > out; close(out); buf = "" }' "$f"
  for s in "$tmp"/*.sql; do
    body="$(cat "$s")"
    printf '%s\n' "$body" | sed -e '/^[[:space:]]*$/d'
    if ! grep -qv '^[[:space:]]*\(--.*\)\{0,1\}$' "$s"; then continue; fi   # comments only
    show "$body" || { rm -rf "$tmp"; return 1; }
    echo
  done
  rm -rf "$tmp"
}
