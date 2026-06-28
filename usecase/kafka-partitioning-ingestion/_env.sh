# _env.sh — robust .env loader shared by the lab scripts. Sourced, not executed.
# Handles inline `# comments`, surrounding quotes and CRLF the way docker-compose
# reads .env. After `load_env`, the .env keys are exported into the environment.
load_env() {
  local f="${1:-.env}"
  [[ -f "$f" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == [[:space:]]*\#* || "$line" == \#* ]] && continue
    [[ "$line" != *=* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    key="${key//[[:space:]]/}"
    case "$val" in *" #"*) val="${val%% #*}";; esac
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}";;
      \'*\') val="${val#\'}"; val="${val%\'}";;
    esac
    export "$key=$val"
  done < "$f"
}

# chc — run a query against the dockerized ClickHouse via clickhouse-client.
chc() { docker compose exec -T clickhouse clickhouse-client "$@"; }
