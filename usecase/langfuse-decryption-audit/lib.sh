# lib.sh — shared helpers for the langfuse-decryption-audit scripts (sourced, not executed).
#
#   LAB_DIR           this directory (from BASH_SOURCE, not $PWD)
#   LANGFUSE_HOLS_DIR the langfuse-hols clone whose v4 stack serves Langfuse (default: a sibling
#                     of this repository); its _base/.env gives the project keys
#   dc                docker compose for this lab
#   bao / kc / audit_sql / lf_sql   OpenBao, Keycloak, audit ClickHouse and Langfuse ClickHouse calls
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANGFUSE_HOLS_DIR="${LANGFUSE_HOLS_DIR:-$(cd "$LAB_DIR/../../.." && pwd)/langfuse-hols}"
ENV_FILE="$LAB_DIR/.env"
STATE="$LAB_DIR/.state"

# read_env <file> <KEY> → value of KEY= in a dotenv file (first match, quotes and inline comment stripped)
read_env() {
  sed -n "s/^$2=//p" "$1" | head -n 1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

load_lab_env() {
  [ -f "$ENV_FILE" ] || { echo "✗ $ENV_FILE missing — run 01-up.sh first"; exit 1; }
  set -a; . "$ENV_FILE"; set +a
}

dc() { docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"; }

BAO_URL=http://127.0.0.1:8200
# bao <METHOD> <path> [json] [extra curl args...] — root token; prints the body, sets nothing
bao() {
  local m=$1 p=$2 d=${3:-}; shift 3 2>/dev/null || shift $#
  curl -sS -m 30 -X "$m" -H "X-Vault-Token: $BAO_ROOT_TOKEN" ${d:+-d "$d"} "$@" "$BAO_URL/v1/$p"
}

KC=http://keycloak:8090
kc() { curl -sS -m 30 --resolve keycloak:8090:127.0.0.1 "$@"; }

# user_token <username> <password> → the user's access token from the corp realm (password grant, lab only)
user_token() {
  kc -f -d grant_type=password -d client_id=decrypt-portal --data-urlencode "username=$1" \
    --data-urlencode "password=$2" "$KC/realms/corp/protocol/openid-connect/token" | jq -r .access_token
}

# audit_sql <user> <password> <sql> → TSV from the audit ClickHouse
audit_sql() {
  curl -sS -m 60 -H "Authorization: Basic $(printf '%s:%s' "$1" "$2" | base64 | tr -d '\n')" "http://127.0.0.1:18123/" --data-binary "$3"
}

# lf_sql <sql> → TSV from Langfuse's own ClickHouse (the langfuse-hols v4 container)
lf_sql() {
  docker exec -i langfuse-hols-v4-clickhouse-1 clickhouse-client --user "${LF_CH_USER:-clickhouse}" \
    --password "${LF_CH_PASSWORD:-clickhouse}" -q "$1"
}

ROWS=""; FAILS=0
# row <check> <expected> <observed> <ok:0|1|info>
row() {
  local res=PASS
  if [ "$4" = info ]; then res=INFO; elif [ "$4" != 1 ]; then res=FAIL; FAILS=$((FAILS+1)); fi
  printf -v ROWS '%s%s\t%s\t%s\t%s\n' "$ROWS" "$1" "$2" "$3" "$res"
  echo "  $res  $1 | expected: $2 | observed: $3"
}
summary() {
  echo; echo "════ Summary ════"; printf '%s' "$ROWS" | column -t -s $'\t'; echo
  if [ "$FAILS" = 0 ]; then echo "✅ all checks passed ($(printf '%s' "$ROWS" | grep -c 'PASS$') PASS, $(printf '%s' "$ROWS" | grep -c 'INFO$') INFO)"
  else echo "✗ $FAILS check(s) failed"; exit 1; fi
}
