#!/usr/bin/env bash
# Starts the five web tools in Docker on this machine, pointed at a ClickHouse Cloud service.
#   ./tools.sh up      ports 18501 CH-UI · 18502 chmonitor · 18503 CH-Ops · 18504 CloudBeaver · 18505 LibreDB Studio
#   ./tools.sh down    removes the containers
# The ClickHouse account comes from CH_HOST / CH_USER / CH_PASSWORD (environment or .env, gitignored).
# Each tool's own admin password is generated once into .tools.env (gitignored, mode 600).
set -euo pipefail
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMES=(osc-chui osc-chmon osc-chops osc-cb osc-libre)
if [ "${1:-}" = down ]; then docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true; echo "removed"; exit 0; fi
[ "${1:-}" = up ] || { echo "usage: $0 up|down" >&2; exit 2; }
if [ -f "$LAB_DIR/.env" ]; then set -a; . "$LAB_DIR/.env"; set +a; fi
: "${CH_HOST:?set CH_HOST (the service hostname, without https://)}" "${CH_PASSWORD:?set CH_PASSWORD}"
TE="$LAB_DIR/.tools.env"
if [ ! -f "$TE" ]; then
  umask 077
  { echo "TOOL_ADMIN_PASSWORD=Ta-$(openssl rand -hex 12)"; echo "CHOPS_KEY=$(openssl rand -hex 32)"; } >"$TE"
fi
set -a; . "$TE"; set +a
URL="https://$CH_HOST:8443"
CH_ENV=$(mktemp); trap 'rm -f "$CH_ENV"' EXIT
printf 'CLICKHOUSE_URL=%s\nCLICKHOUSE_HOST=%s\nCLICKHOUSE_USER=%s\nCLICKHOUSE_PASSWORD=%s\n' \
  "$URL" "$URL" "${CH_USER:-default}" "$CH_PASSWORD" >"$CH_ENV"
docker rm -f "${NAMES[@]}" >/dev/null 2>&1 || true
docker run -d --name osc-chui  -p 18501:3488 --env-file "$CH_ENV" ghcr.io/caioricciuti/ch-ui:v2.33.0 >/dev/null
docker run -d --name osc-chmon -p 18502:3000 --env-file "$CH_ENV" ghcr.io/chmonitor/chmonitor:0.3.11 >/dev/null
# CH-Ops refuses to start without its first super admin in the environment; connections are added in its UI.
docker run -d --name osc-chops -p 18503:3000 -e ENCRYPTION_SECRET="$CHOPS_KEY" -e SUPER_ADMIN_1=admin \
  -e SUPER_ADMIN_1_EMAIL=admin@consoles.test -e SUPER_ADMIN_1_PASSWORD="$TOOL_ADMIN_PASSWORD" ghcr.io/quantrail-data/ch-ops:1.3.3 >/dev/null
# CloudBeaver: admin and connection are created in its first-run wizard.
docker run -d --name osc-cb    -p 18504:8978 dbeaver/cloudbeaver:26.2.0 >/dev/null
docker run -d --name osc-libre -p 18505:3000 -e AUTH_COOKIE_SECURE=false -e ADMIN_EMAIL=admin@consoles.test \
  -e ADMIN_PASSWORD="$TOOL_ADMIN_PASSWORD" ghcr.io/libredb/libredb-studio:1.2.0 >/dev/null
echo "started; tool admin login: admin / admin@consoles.test with TOOL_ADMIN_PASSWORD from .tools.env"
for p in 18501 18502 18503 18504 18505; do
  for _ in $(seq 30); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$p/" && break; sleep 2; done
  echo "localhost:$p -> HTTP $(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$p/")"
done
