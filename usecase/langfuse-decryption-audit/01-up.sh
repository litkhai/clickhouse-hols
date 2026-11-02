#!/usr/bin/env bash
# 01-up.sh — start OpenBao, Keycloak, the audit ClickHouse and the decryption service, and configure them.
#
# Needs the langfuse-hols v4 stack running (`_base/bin/up.sh v4` in that repository; no licence key
# needed). Generates .env (mode 600, gitignored) with every password on first run and reuses it.
# OpenBao runs in dev mode (in memory), so its configuration is applied again on every run.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for c in docker jq curl openssl; do command -v "$c" >/dev/null || { echo "✗ please install $c"; exit 1; }; done

LF_ENV="$LANGFUSE_HOLS_DIR/_base/.env"
[ -f "$LF_ENV" ] || { echo "✗ $LF_ENV not found — clone langfuse-hols next to this repository or set LANGFUSE_HOLS_DIR"; exit 1; }
LF_HOST_ON_HOST="$(read_env "$LF_ENV" NEXTAUTH_URL)"; LF_HOST_ON_HOST="${LF_HOST_ON_HOST:-http://localhost:3000}"
[ "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$LF_HOST_ON_HOST/api/public/health")" = 200 ] ||
  { echo "✗ Langfuse is not answering at $LF_HOST_ON_HOST — start it: (cd $LANGFUSE_HOLS_DIR && _base/bin/up.sh v4)"; exit 1; }

echo "════ 1. .env (generated once, mode 600) ════"
if [ ! -f "$ENV_FILE" ]; then
  umask 077
  {
    echo "BAO_ROOT_TOKEN=$(openssl rand -hex 16)"
    echo "KC_ADMIN_PASSWORD=$(openssl rand -hex 16)"
    echo "CH_ADMIN_PASSWORD=$(openssl rand -hex 16)"
    echo "AUDIT_WRITER_PASSWORD=$(openssl rand -hex 16)"
    echo "AUDITOR_PASSWORD=$(openssl rand -hex 16)"
    for u in alice bob carol; do echo "PW_$u=Aa1!$(openssl rand -hex 12)"; done
  } > "$ENV_FILE"
  echo "  written $ENV_FILE"
fi
# Langfuse project keys are re-read from langfuse-hols on every run.
sed -i.bak -e '/^LANGFUSE_/d' -e '/^LF_CH_/d' -e '/^APP_ENCRYPT_TOKEN=/d' "$ENV_FILE" && rm -f "$ENV_FILE.bak"
{
  echo "LANGFUSE_HOST=$LF_HOST_ON_HOST"
  echo "LANGFUSE_PUBLIC_KEY=$(read_env "$LF_ENV" LANGFUSE_PUBLIC_KEY)"
  echo "LANGFUSE_SECRET_KEY=$(read_env "$LF_ENV" LANGFUSE_SECRET_KEY)"
  echo "LF_CH_USER=$(read_env "$LF_ENV" CLICKHOUSE_USER)"
  echo "LF_CH_PASSWORD=$(read_env "$LF_ENV" CLICKHOUSE_PASSWORD)"
} >> "$ENV_FILE"
chmod 600 "$ENV_FILE"
load_lab_env

echo "════ 2. Containers ════"
dc up -d >/dev/null 2>&1
for _ in $(seq 1 60); do curl -sf -o /dev/null "$BAO_URL/v1/sys/health" 2>/dev/null && break; sleep 2; done
for _ in $(seq 1 90); do kc -sf -o /dev/null "$KC/realms/corp/.well-known/openid-configuration" 2>/dev/null && break; sleep 2; done
for _ in $(seq 1 60); do curl -sf -o /dev/null http://127.0.0.1:8095/health 2>/dev/null && break; sleep 2; done
echo "  openbao $(curl -s "$BAO_URL/v1/sys/health" | jq -r .version) · keycloak realm corp · audit ClickHouse · decrypt-service"

echo "════ 3. OpenBao: Transit keys, policies, JWT auth against Keycloak ════"
bao POST sys/mounts/transit '{"type":"transit"}' -o /dev/null
for k in svc-a svc-b; do bao POST "transit/keys/$k" '{}' -o /dev/null; done
# The X-Request-Id header is written to the audit log unhashed, so it can be joined to the service's rows.
bao POST sys/config/auditing/request-headers/X-Request-Id '{"hmac":false}' -o /dev/null
put_policy() { jq -n --arg p "$2" '{policy:$p}' | curl -sS -m 30 -o /dev/null -X PUT -H "X-Vault-Token: $BAO_ROOT_TOKEN" -d @- "$BAO_URL/v1/sys/policies/acl/$1"; }
put_policy app-encrypt 'path "transit/encrypt/*" { capabilities = ["update"] }'
for k in svc-a svc-b; do put_policy "decrypt-$k" "path \"transit/decrypt/$k\" { capabilities = [\"update\"] }"; done
bao POST sys/auth/jwt '{"type":"jwt"}' -o /dev/null
bao POST auth/jwt/config "{\"oidc_discovery_url\":\"$KC/realms/corp\",\"bound_issuer\":\"$KC/realms/corp\"}" -o /dev/null
for k in svc-a svc-b; do
  jq -n --arg g "$k-readers" --arg p "decrypt-$k" '{role_type:"jwt", bound_audiences:["openbao"], user_claim:"preferred_username",
      groups_claim:"groups", bound_claims:{groups:[$g]}, claim_mappings:{preferred_username:"username", email:"email"},
      token_policies:[$p], token_ttl:"5m", token_max_ttl:"5m"}' |
    curl -sS -m 30 -o /dev/null -X POST -H "X-Vault-Token: $BAO_ROOT_TOKEN" -d @- "$BAO_URL/v1/auth/jwt/role/reader-$k"
done
# The application's token: encrypt only, on both keys. In production this is the app's own auth (AppRole, Kubernetes, managed identity).
APP=$(bao POST auth/token/create '{"policies":["app-encrypt"],"no_default_policy":true,"ttl":"24h","display_name":"app-encryptor"}' | jq -r .auth.client_token)
echo "APP_ENCRYPT_TOKEN=$APP" >> "$ENV_FILE"
echo "  keys svc-a, svc-b · roles reader-svc-a, reader-svc-b · app token (encrypt only)"

echo "════ 4. Audit ClickHouse: table and two users ════"
asql() { audit_sql admin "$CH_ADMIN_PASSWORD" "$1"; }
sed -e 's/--.*$//' "$LAB_DIR/clickhouse/schema.sql" | tr '\n' ' ' | tr ';' '\n' | while IFS= read -r s; do
  [ -n "${s// /}" ] && asql "$s" >/dev/null
done
asql "CREATE USER IF NOT EXISTS audit_writer IDENTIFIED WITH sha256_password BY '$AUDIT_WRITER_PASSWORD'" >/dev/null
asql "CREATE USER IF NOT EXISTS auditor IDENTIFIED WITH sha256_password BY '$AUDITOR_PASSWORD'" >/dev/null
asql "GRANT INSERT ON audit.decrypt_events TO audit_writer" >/dev/null
asql "GRANT SELECT ON audit.decrypt_events TO auditor" >/dev/null
asql "GRANT READ ON FILE TO auditor" >/dev/null
# IN (subquery) builds a temporary set; on 26.8 that needs this grant, or the reconciliation fails with Code 497.
asql "GRANT CREATE TEMPORARY TABLE ON *.* TO auditor" >/dev/null
echo "  audit.decrypt_events · audit_writer (INSERT) · auditor (SELECT, READ ON FILE, CREATE TEMPORARY TABLE)"

echo "════ 5. Keycloak: users and groups ════"
KTOK=$(kc -f -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode "password=$KC_ADMIN_PASSWORD" \
  "$KC/realms/master/protocol/openid-connect/token" | jq -r .access_token)
mkuser() {  # mkuser <name> <group or "">
  local pw_var="PW_$1"
  local body; body=$(jq -n --arg u "$1" --arg p "${!pw_var}" --arg g "$2" '{username:$u, email:($u+"@corp.test"), emailVerified:true,
    firstName:$u, lastName:"Lab", enabled:true, credentials:[{type:"password", value:$p, temporary:false}],
    groups:(if $g == "" then [] else [$g] end)}')
  local code; code=$(kc -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $KTOK" -H "Content-Type: application/json" \
    "$KC/admin/realms/corp/users" -d "$body")
  [ "$code" = 201 ] || [ "$code" = 409 ] || { echo "✗ creating $1: HTTP $code"; exit 1; }
}
mkuser alice svc-a-readers; mkuser bob ""; mkuser carol svc-b-readers
echo "  alice (svc-a-readers) · bob (no group) · carol (svc-b-readers)"
echo
echo "✅ up. Next: ./02-encrypt-and-send.sh"
