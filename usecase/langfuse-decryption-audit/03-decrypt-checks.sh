#!/usr/bin/env bash
# 03-decrypt-checks.sh — who may decrypt, what gets recorded, and what the record catches.
#
# Requests to the decryption service (each one positive or negative):
#   alice  (svc-a-readers) A + reason   → 200, plaintext
#   carol  (svc-b-readers) B + reason   → 200, plaintext
#   alice                  B            → 403 (OpenBao refuses the svc-b role: group claim does not match)
#   bob    (no group)      A            → 403
#   alice                  A, no reason → 400
#   no token                            → 401
#   alice's token with groups and name edited, signature kept → 403 (OpenBao rejects the signature)
#   audit store down                    → 503, no plaintext, and OpenBao was never asked to decrypt
# Then a decryption that bypasses the service (alice straight to OpenBao) and the checks on the trail:
#   the service rows, OpenBao's audit file read from ClickHouse with file(), the reconciliation that
#   finds the bypass, no plaintext or token in OpenBao's audit file, and an audit table that neither
#   the writer nor the auditor can change.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
[ -f "$STATE" ] || { echo "✗ run 02-encrypt-and-send.sh first"; exit 1; }
. "$STATE"
SVC=http://127.0.0.1:8095
REASON="ticket LAB-$RUN: customer asked to check the account on file"
# This script's own start: every check below counts only what happened after it (a re-run does not add up).
CHECK_START=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 1

# dec <token or ""> <trace id> <reason> → "<http code> <json body>"
dec() {
  local auth=(); [ -n "$1" ] && auth=(-H "Authorization: Bearer $1")
  jq -n --arg t "$2" --arg r "$3" '{trace_id:$t, field:"input", reason:$r}' |
    curl -sS -m 30 -w '\n%{http_code}' -X POST "$SVC/decrypt" ${auth[@]+"${auth[@]}"} -H "Content-Type: application/json" -d @- |
    awk 'NR==1{b=$0;next}{print $0" "b}'
}
code() { echo "${1%% *}"; }
body() { echo "${1#* }"; }

echo "════ 1. Requests to the decryption service ════"
T_ALICE=$(user_token alice "$PW_alice"); T_BOB=$(user_token bob "$PW_bob"); T_CAROL=$(user_token carol "$PW_carol")
[ -n "$T_ALICE" ] && [ "$T_ALICE" != null ] || { echo "✗ no token for alice"; exit 1; }

r=$(dec "$T_ALICE" "$TA" "$REASON"); RID_OK_A=$(body "$r" | jq -r .request_id)
[ "$(code "$r")" = 200 ] && [ "$(body "$r" | jq -r .plaintext)" = "$PA" ] && ok=1 || ok=0
row "alice decrypts A (svc-a) with a reason" "200 + A's plaintext" "$(code "$r") $(body "$r" | jq -r '.plaintext // .detail')" $ok
r=$(dec "$T_CAROL" "$TB" "$REASON"); RID_OK_B=$(body "$r" | jq -r .request_id)
[ "$(code "$r")" = 200 ] && [ "$(body "$r" | jq -r .plaintext)" = "$PB" ] && ok=1 || ok=0
row "carol decrypts B (svc-b) with a reason" "200 + B's plaintext" "$(code "$r") $(body "$r" | jq -r '.plaintext // .detail')" $ok
r=$(dec "$T_ALICE" "$TB" "$REASON"); [ "$(code "$r")" = 403 ] && ok=1 || ok=0
row "alice asks for B (svc-b)" 403 "$(code "$r") $(body "$r" | jq -r .detail | cut -c1-80)" $ok
r=$(dec "$T_BOB" "$TA" "$REASON"); [ "$(code "$r")" = 403 ] && ok=1 || ok=0
row "bob (no group) asks for A" 403 "$(code "$r") $(body "$r" | jq -r .detail | cut -c1-80)" $ok
r=$(dec "$T_ALICE" "$TA" ""); [ "$(code "$r")" = 400 ] && ok=1 || ok=0
row "alice asks for A without a reason" 400 "$(code "$r") $(body "$r" | jq -r .detail)" $ok
r=$(dec "" "$TA" "$REASON"); [ "$(code "$r")" = 401 ] && ok=1 || ok=0
row "no token" 401 "$(code "$r") $(body "$r" | jq -r .detail)" $ok
FORGED=$(python3 -I - "$T_ALICE" <<'PY'
import base64, json, sys
h, p, s = sys.argv[1].split(".")
c = json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))
c["groups"], c["preferred_username"] = ["svc-b-readers"], "carol"
print(h + "." + base64.urlsafe_b64encode(json.dumps(c).encode()).rstrip(b"=").decode() + "." + s)
PY
)
r=$(dec "$FORGED" "$TB" "$REASON"); [ "$(code "$r")" = 403 ] && ok=1 || ok=0
row "alice's token edited to carol/svc-b, signature kept" 403 "$(code "$r") $(body "$r" | jq -r .detail | cut -c1-80)" $ok

dc stop clickhouse-audit >/dev/null 2>&1
r=$(dec "$T_ALICE" "$TA" "$REASON"); RID_DOWN=$(body "$r" | jq -r '.request_id // empty')
[ "$(code "$r")" = 503 ] && [ "$(body "$r" | jq -r '.plaintext // empty')" = "" ] && ok=1 || ok=0
row "audit store down: alice asks for A" "503, no plaintext" "$(code "$r") $(body "$r" | jq -r .error)" $ok
dc start clickhouse-audit >/dev/null 2>&1
for _ in $(seq 1 60); do audit_sql auditor "$AUDITOR_PASSWORD" "SELECT 1" >/dev/null 2>&1 && break; sleep 2; done

echo "════ 2. A decryption that bypasses the service ════"
# alice has the right to decrypt svc-a; here she goes to OpenBao herself, with no reason and no service row.
BT=$(curl -sS -m 30 -X POST "$BAO_URL/v1/auth/jwt/login" -d "{\"role\":\"reader-svc-a\",\"jwt\":\"$T_ALICE\"}" | jq -r .auth.client_token)
CA=$(curl -s -m 30 -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$LANGFUSE_HOST/api/public/v2/observations?traceId=$TA&fields=core,io" |
  jq -r '.data[0].input' | cut -d: -f3-)
pt=$(curl -sS -m 30 -X POST -H "X-Vault-Token: $BT" -d "{\"ciphertext\":\"$CA\"}" "$BAO_URL/v1/transit/decrypt/svc-a" | jq -r .data.plaintext | base64 -d)
[ "$pt" = "$PA" ] && ok=1 || ok=0; row "alice decrypts A directly at OpenBao" "A's plaintext (she holds the right)" "$pt" $ok

echo "════ 3. The service's rows (as auditor) ════"
A() { audit_sql auditor "$AUDITOR_PASSWORD" "$1"; }
SINCE="event_time >= parseDateTimeBestEffort('$CHECK_START')"
o=$(A "SELECT outcome, count() FROM audit.decrypt_events WHERE $SINCE GROUP BY outcome ORDER BY outcome FORMAT CSV" | tr -d '"' | paste -sd' ' -)
[ "$o" = "attempt,2 denied,3 reason_missing,1 success,2 unauthenticated,1" ] && ok=1 || ok=0
row "rows by outcome since the run started" "attempt,2 denied,3 reason_missing,1 success,2 unauthenticated,1" "$o" $ok
o=$(A "SELECT concat(user, '|', key_name, '|', trace_id = '$TA', '|', reason != '') FROM audit.decrypt_events WHERE request_id = '$RID_OK_A' AND outcome = 'success'")
[ "$o" = "alice|svc-a|1|1" ] && ok=1 || ok=0; row "alice's success row: user, key, trace, reason" "alice|svc-a|1|1" "$o" $ok
o=$(A "SELECT arrayStringConcat(arraySort(groupArray(concat(claimed_user, ':', if(user = '', '-', user)))), ' ') FROM audit.decrypt_events WHERE $SINCE AND outcome = 'denied'")
[ "$o" = "alice:- bob:- carol:-" ] && ok=1 || ok=0
row "denied rows: claimed user, verified user" "alice:- bob:- carol:- (carol = the edited token)" "$o" $ok
n=$(A "SELECT count() FROM audit.decrypt_events WHERE $SINCE AND (reason LIKE '%$PA%' OR detail LIKE '%$PA%' OR reason LIKE '%$PB%' OR detail LIKE '%$PB%')")
[ "$n" = 0 ] && ok=1 || ok=0; row "plaintext in the audit table" 0 "$n" $ok
n=$(docker logs langfuse-decryption-audit-decrypt-service-1 2>&1 | grep -cF -e "$PA" -e "$PB" || true)
[ "$n" = 0 ] && ok=1 || ok=0; row "plaintext in the service's container log" 0 "$n" $ok

echo "════ 4. OpenBao's audit file, read from ClickHouse (file()) ════"
BAO_SRC="file('openbao/audit.log', 'JSONAsString')"
BAO_SINCE="JSONExtractString(json, 'time') >= '$CHECK_START'"
RID="JSONExtract(json, 'request', 'headers', 'x-request-id', 'Array(String)')[1]"
DEC_OK="JSONExtractString(json, 'type') = 'response' AND startsWith(JSONExtractString(json, 'request', 'path'), 'transit/decrypt/') AND NOT JSONHas(json, 'error')"
o=$(A "SELECT concat(JSONExtractString(json, 'auth', 'metadata', 'username'), '|', JSONExtractString(json, 'request', 'path')) FROM $BAO_SRC WHERE $BAO_SINCE AND $DEC_OK AND $RID = '$RID_OK_A'")
[ "$o" = "alice|transit/decrypt/svc-a" ] && ok=1 || ok=0
row "OpenBao entry for alice's request id: user, path" "alice|transit/decrypt/svc-a" "$o" $ok
n=$(A "SELECT count() FROM $BAO_SRC WHERE $BAO_SINCE AND $DEC_OK AND $RID = '$RID_DOWN'")
[ "$n" = 0 ] && ok=1 || ok=0; row "OpenBao decrypts for the request made while the audit store was down" 0 "$n" $ok
n=$(A "SELECT count() FROM $BAO_SRC WHERE $BAO_SINCE AND JSONExtractString(json, 'type') = 'response' AND JSONExtractString(json, 'request', 'path') = 'auth/jwt/login' AND JSONHas(json, 'response', 'data', 'error') AND $RID IN (SELECT toString(request_id) FROM audit.decrypt_events WHERE $SINCE AND outcome = 'denied')")
[ "$n" = 3 ] && ok=1 || ok=0; row "OpenBao refused logins matching the service's denied rows" 3 "$n" $ok
# A refused login is a normal response with response.data.error, and that message is HMAC'd: OpenBao's
# file says THAT a login failed, the service row says WHY.
o=$(A "SELECT any(startsWith(JSONExtractString(json, 'response', 'data', 'error'), 'hmac-sha256:')) FROM $BAO_SRC WHERE $BAO_SINCE AND JSONHas(json, 'response', 'data', 'error')")
[ "$o" = 1 ] && ok=1 || ok=0; row "OpenBao's refusal message in its audit file" "HMAC'd" "$([ "$o" = 1 ] && echo "hmac-sha256:…" || echo "$o")" $ok
o=$(A "SELECT concat(toString(count()), ' ', arrayStringConcat(groupUniqArray(JSONExtractString(json, 'auth', 'metadata', 'username')), ',')) FROM $BAO_SRC
       WHERE $BAO_SINCE AND $DEC_OK AND $RID NOT IN (SELECT toString(request_id) FROM audit.decrypt_events WHERE $SINCE AND outcome = 'attempt')")
[ "$o" = "1 alice" ] && ok=1 || ok=0
row "reconciliation: OpenBao decrypts with no service attempt row" "1 alice (the bypass)" "$o" $ok
n=$(A "SELECT count() FROM $BAO_SRC WHERE position(json, '$PA') > 0 OR position(json, '$PB') > 0 OR position(json, '$(printf '%s' "$PA" | base64)') > 0")
[ "$n" = 0 ] && ok=1 || ok=0; row "plaintext (raw or base64) in OpenBao's audit file" 0 "$n" $ok
n=$(A "SELECT count() FROM $BAO_SRC WHERE position(json, '$(echo "$T_ALICE" | cut -d. -f3)') > 0")
[ "$n" = 0 ] && ok=1 || ok=0; row "alice's token (signature part) in OpenBao's audit file" 0 "$n" $ok
n=$(A "SELECT count() FROM $BAO_SRC WHERE position(json, '$RID_OK_A') > 0")
[ "$n" -ge 1 ] && ok=1 || ok=0; row "control: the request id in clear in the same file" ">=1" "$n" $ok

echo "════ 5. Nobody edits the trail ════"
denied() { echo "$1" | grep -q 'ACCESS_DENIED\|Not enough privileges' && echo 1 || echo 0; }
W() { audit_sql audit_writer "$AUDIT_WRITER_PASSWORD" "$1" 2>&1; }
row "audit_writer: SELECT" "denied" "$(W "SELECT count() FROM audit.decrypt_events" | grep -oE 'Code: [0-9]+' | head -1)" "$(denied "$(W "SELECT count() FROM audit.decrypt_events")")"
row "audit_writer: ALTER TABLE … DELETE" "denied" "$(W "ALTER TABLE audit.decrypt_events DELETE WHERE 1" | grep -oE 'Code: [0-9]+' | head -1)" "$(denied "$(W "ALTER TABLE audit.decrypt_events DELETE WHERE 1")")"
row "audit_writer: TRUNCATE" "denied" "$(W "TRUNCATE TABLE audit.decrypt_events" | grep -oE 'Code: [0-9]+' | head -1)" "$(denied "$(W "TRUNCATE TABLE audit.decrypt_events")")"
row "auditor: INSERT" "denied" "$(A "INSERT INTO audit.decrypt_events (request_id) VALUES (generateUUIDv4())" 2>&1 | grep -oE 'Code: [0-9]+' | head -1)" "$(denied "$(A "INSERT INTO audit.decrypt_events (request_id) VALUES (generateUUIDv4())" 2>&1)")"
row "auditor: ALTER TABLE … UPDATE" "denied" "$(A "ALTER TABLE audit.decrypt_events UPDATE reason = '' WHERE 1" 2>&1 | grep -oE 'Code: [0-9]+' | head -1)" "$(denied "$(A "ALTER TABLE audit.decrypt_events UPDATE reason = '' WHERE 1" 2>&1)")"
n=$(A "SELECT count() FROM audit.decrypt_events WHERE $SINCE")
[ "$n" = 9 ] && ok=1 || ok=0; row "rows after the attempts above (unchanged)" 9 "$n" $ok

summary
