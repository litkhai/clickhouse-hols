# lib.sh — shared helpers for the langfuse-prompt-encryption-perf scripts (sourced, not executed).
#
#   LAB_DIR            this directory
#   LANGFUSE_HOLS_DIR  the langfuse-hols clone whose v4 stack 07-langfuse-e2e.sh uses (default: a sibling)
#   dc                 docker compose for the bench stack (project prompt-enc)
#   ch                 clickhouse-client inside the bench ClickHouse, as user bench
#   bao                OpenBao HTTP call with the root token
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANGFUSE_HOLS_DIR="${LANGFUSE_HOLS_DIR:-$(cd "$LAB_DIR/../../.." && pwd)/langfuse-hols}"
ENV_FILE="$LAB_DIR/.env"
SECRETS_DIR="$LAB_DIR/.secrets"
RESULTS_DIR="$LAB_DIR/results"

load_lab_env() {
  [ -f "$ENV_FILE" ] || { echo "✗ $ENV_FILE missing — run 01-up.sh first"; exit 1; }
  set -a; . "$ENV_FILE"; set +a
}

dc() { docker compose --project-directory "$LAB_DIR" -f "$LAB_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"; }

# ch [clickhouse-client args...] — runs inside the bench container
ch() { docker exec -i prompt-enc-ch-1 clickhouse-client --user bench --password "$CH_PASSWORD" "$@"; }

BAO_URL=http://127.0.0.1:8210
bao() {
  local m=$1 p=$2 d=${3:-}
  curl -sS -m 30 -X "$m" -H "X-Vault-Token: $BAO_ROOT_TOKEN" ${d:+-d "$d"} "$BAO_URL/v1/$p"
}

say()  { printf '\n▶ %s\n' "$*"; }
pass() { printf '  PASS  %s\n' "$*"; PASSES=$((${PASSES:-0}+1)); }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((${FAILS:-0}+1)); }
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1 (expected $2, got $3)"; fi
}
