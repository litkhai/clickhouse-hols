#!/usr/bin/env bash
# 02-encrypt-and-send.sh — play the application: encrypt a field with OpenBao Transit, send the trace to Langfuse.
#
# Three traces, one OTLP root span each:
#   A  input encrypted with key svc-a      → `enc:svc-a:vault:v1:...`
#   B  input encrypted with key svc-b      → `enc:svc-b:vault:v1:...`
#   C  control: the same kind of value in plaintext
# The values are made-up account strings with a per-run random part. Checks: Langfuse's API and its
# ClickHouse hold only ciphertext for A and B, and the control's plaintext is found by the same query.
# In an SDK the encryption sits in the export hook (langfuse-hols labs/v4/langfuse-ee step 14);
# here curl stands in for the application so the lab needs no Python packages.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env

encrypt() {  # encrypt <key> <plaintext> → enc:<key>:<OpenBao ciphertext>, with the app's encrypt-only token
  local c; c=$(jq -n --arg p "$(printf '%s' "$2" | base64)" '{plaintext:$p}' |
    curl -sS -m 30 -X POST -H "X-Vault-Token: $APP_ENCRYPT_TOKEN" -d @- "$BAO_URL/v1/transit/encrypt/$1" | jq -r .data.ciphertext)
  [ "${c#vault:v}" != "$c" ] || { echo "✗ encrypt with $1 failed"; exit 1; }
  echo "enc:$1:$c"
}
send() {  # send <input value> → trace id
  local tid; tid=$(openssl rand -hex 16); local nano; nano="$(date +%s)000000000"
  jq -n --arg tid "$tid" --arg sid "$(openssl rand -hex 8)" --arg n "$nano" --arg v "$1" \
    '{resourceSpans:[{resource:{attributes:[{key:"service.name",value:{stringValue:"decryption-audit-lab"}}]},
      scopeSpans:[{scope:{name:"decryption-audit-lab"},spans:[{traceId:$tid,spanId:$sid,name:"support-chat",kind:1,
      startTimeUnixNano:$n,endTimeUnixNano:$n,attributes:[{key:"langfuse.observation.input",value:{stringValue:$v}}]}]}]}]}' |
    curl -fsS -m 30 -o /dev/null -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" -X POST "$LANGFUSE_HOST/api/public/otel/v1/traces" \
      -H "Content-Type: application/json" -H "x-langfuse-ingestion-version: 4" -d @-
  echo "$tid"
}
api_input() {  # api_input <trace id> → the input the public API returns (waits for async ingestion)
  local v=""
  for _ in $(seq 1 40); do
    v=$(curl -s -m 30 -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
      "$LANGFUSE_HOST/api/public/v2/observations?traceId=$1&fields=core,io" | jq -r '.data[0].input // empty' 2>/dev/null || true)
    [ -n "$v" ] && break; sleep 3
  done
  echo "$v"
}

RUN=$(openssl rand -hex 6)
PA="acct-LAB-A-$RUN"; PB="acct-LAB-B-$RUN"; PC="acct-LAB-C-$RUN"

echo "════ 1. The app token can encrypt, and cannot decrypt ════"
EA=$(encrypt svc-a "$PA"); EB=$(encrypt svc-b "$PB")
row "encrypt with svc-a and svc-b (app token)" "enc:<key>:vault:v1:…" "${EA:0:22}… ${EB:0:22}…" 1
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "X-Vault-Token: $APP_ENCRYPT_TOKEN" \
  -d "{\"ciphertext\":\"${EA#enc:svc-a:}\"}" "$BAO_URL/v1/transit/decrypt/svc-a")
[ "$code" = 403 ] && ok=1 || ok=0; row "decrypt with the app token" "HTTP 403" "HTTP $code" $ok

echo "════ 2. Send to Langfuse (OTLP) ════"
TA=$(send "$EA"); TB=$(send "$EB"); TC=$(send "$PC")
{ echo "RUN=$RUN"; echo "TA=$TA"; echo "TB=$TB"; echo "TC=$TC"; echo "PA=$PA"; echo "PB=$PB"; echo "PC=$PC"
  echo "RUN_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$STATE"
chmod 600 "$STATE"
echo "  traces A=$TA B=$TB C(control)=$TC"

echo "════ 3. What Langfuse stores ════"
v=$(api_input "$TA"); [ "$v" = "$EA" ] && ok=1 || ok=0; row "API input of A" "the ciphertext" "${v:0:30}…" $ok
v=$(api_input "$TB"); [ "$v" = "$EB" ] && ok=1 || ok=0; row "API input of B" "the ciphertext" "${v:0:30}…" $ok
v=$(api_input "$TC"); [ "$v" = "$PC" ] && ok=1 || ok=0; row "API input of C (control)" "the plaintext" "$v" $ok
n=$(lf_sql "SELECT count() FROM events_full WHERE input LIKE '%$PA%' OR input LIKE '%$PB%'")
[ "$n" = 0 ] && ok=1 || ok=0; row "Langfuse ClickHouse rows holding A's or B's plaintext" 0 "$n" $ok
n=$(lf_sql "SELECT count() FROM events_full WHERE input LIKE '%$PC%'")
[ "$n" -ge 1 ] && ok=1 || ok=0; row "control: rows holding C's plaintext" ">=1" "$n" $ok
summary
