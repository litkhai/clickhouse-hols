#!/usr/bin/env bash
# Real ClickHouse -> catalog integration test.
#
# For each catalog: seed lab.events (5 rows) THROUGH the catalog with a pinned writer
# (seed_catalogs.py in a pinned python container), then in ClickHouse
#   CREATE DATABASE ... ENGINE = DataLakeCatalog(...)  ->  SHOW TABLES, count, filter, typed values
# and compare with what was seeded. PASS only if ClickHouse read the seeded rows via the catalog.
#
# Usage: tests/test-datalakecatalog.sh [nessie] [hive] [iceberg-rest] [polaris] [unity]   (default: all)
# Env (all optional):
#   CH_IMAGE          ClickHouse image                 (default clickhouse/clickhouse-server:26.10.3.7)
#   COMPOSE_PROJECT   compose project / network prefix (default dlfix)
#   FAULT=stop-catalog  stop each catalog after seeding; the test must then go red
#   UNITY_V2=0        create the Unity database without use_unity_catalog_v2
#   UNITY_STORAGE_ENDPOINT=   (empty) omit storage_endpoint for Unity: ClickHouse then goes to AWS S3 and must fail
#   KEEP=1            leave the stack and ClickHouse container running
#   MINIO_PORT, MINIO_CONSOLE_PORT, POSTGRES_PORT, ...  host ports, as in config.env
set -u

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB"

# config.env supplies defaults; anything already in the environment wins.
while IFS='=' read -r k v; do
  [[ "$k" =~ ^[A-Z_0-9]+$ ]] || continue
  [ -z "${!k+x}" ] && export "$k=$v"
done < <(grep -E '^[A-Z_0-9]+=' config.env)

CH_IMAGE="${CH_IMAGE:-clickhouse/clickhouse-server:26.10.3.7}"
PY_IMAGE="python@sha256:b18b261e1b4974b4f321451ad5251ded85abb22c2b8b262da527dda1d031ab30" # python:3.12-slim, 2026-11-04
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT:-dlfix}"
NET="${COMPOSE_PROJECT_NAME}_datalake"
CH="${COMPOSE_PROJECT_NAME}-clickhouse"
FAULT="${FAULT:-none}"
CATALOGS=("$@"); [ ${#CATALOGS[@]} -eq 0 ] && CATALOGS=(nessie hive iceberg-rest polaris unity)
WORK="$(mktemp -d)"
BUCKET="${SAMPLE_DATA_BUCKET:-warehouse}"
PROFILES=(); for c in "${CATALOGS[@]}"; do PROFILES+=(--profile "$c"); done
container() { case "$1" in hive) echo hive-metastore;; unity) echo unity-catalog;; *) echo "$1";; esac; }  # no assoc arrays: macOS bash 3.2

dc() { docker compose "${PROFILES[@]}" "$@"; }
cleanup() {
  if [ "${KEEP:-0}" != 1 ]; then
    docker rm -f "$CH" >/dev/null 2>&1
    docker compose --profile nessie --profile hive --profile iceberg-rest --profile polaris --profile unity down -v >/dev/null 2>&1
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

pyrun() { # pyrun <args...>: pinned python container on the lab network
  docker run --rm --network "$NET" -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD -e SAMPLE_DATA_BUCKET="$BUCKET" \
    -v "$LAB/tests:/t:ro" -v "$WORK:/out" "$PY_IMAGE" sh -c \
    "pip install -q --root-user-action=ignore --disable-pip-version-check -r /t/requirements-seed.txt && python /t/seed_catalogs.py $*"
}

echo "== ClickHouse image: $CH_IMAGE   fault: $FAULT   catalogs: ${CATALOGS[*]}"

# --- storage -----------------------------------------------------------------------------
dc up -d minio minio-setup >/dev/null || exit 2
for _ in $(seq 1 40); do
  [ "$(docker inspect -f '{{.State.Status}}/{{.State.ExitCode}}' minio-setup 2>/dev/null)" = "exited/0" ] && break
  sleep 2
done
echo "minio-setup: $(docker inspect -f '{{.State.Status}}/{{.State.ExitCode}}' minio-setup)"

# --- catalogs ----------------------------------------------------------------------------
if [[ " ${CATALOGS[*]} " == *" unity "* ]]; then
  pyrun unity-props /out/server.properties || exit 2
  export UNITY_SERVER_PROPERTIES="$WORK/server.properties"
fi
SERVICES=(); for c in "${CATALOGS[@]}"; do SERVICES+=("$(container "$c")"); done
dc up -d "${SERVICES[@]}" >/dev/null || exit 2

# --- seed through each catalog ---------------------------------------------------------------
echo "== seeding"
pyrun "${CATALOGS[*]}" 2>&1 | grep -v -E '^(WARNING|\[notice\])' || { echo "seeding failed"; exit 2; }

# --- ClickHouse ----------------------------------------------------------------------------
docker rm -f "$CH" >/dev/null 2>&1
docker run -d --name "$CH" --network "$NET" "$CH_IMAGE" >/dev/null || exit 2
for _ in $(seq 1 30); do docker exec "$CH" clickhouse-client -q "SELECT 1" >/dev/null 2>&1 && break; sleep 2; done
VERSION="$(docker exec "$CH" clickhouse-client -q "SELECT version()")"
echo "== ClickHouse $VERSION"

chq() { docker exec "$CH" clickhouse-client --allow_database_iceberg=1 --allow_database_unity_catalog=1 \
          --allow_experimental_database_hms_catalog=1 -q "$1" 2>&1; }

S3="vended_credentials = 0, aws_access_key_id = '${MINIO_ROOT_USER}', aws_secret_access_key = '${MINIO_ROOT_PASSWORD}', region = 'us-east-1', storage_endpoint = 'http://minio:9000/${BUCKET}'"
UEP="${UNITY_STORAGE_ENDPOINT-http://minio:9000}"   # set empty to omit it (negative control)
ddl() { case "$1" in
  nessie)       echo "CREATE DATABASE lake ENGINE = DataLakeCatalog('http://nessie:19120/iceberg') SETTINGS catalog_type = 'rest', warehouse = 'warehouse', $S3" ;;
  iceberg-rest) echo "CREATE DATABASE lake ENGINE = DataLakeCatalog('http://iceberg-rest:8181') SETTINGS catalog_type = 'rest', warehouse = 'warehouse', $S3" ;;
  polaris)      echo "CREATE DATABASE lake ENGINE = DataLakeCatalog('http://polaris:8181/api/catalog') SETTINGS catalog_type = 'rest', warehouse = 'polaris_lab', catalog_credential = 'root:s3cr3t', auth_scope = 'PRINCIPAL_ROLE:ALL', oauth_server_uri = 'http://polaris:8181/api/catalog/v1/oauth/tokens', $S3" ;;
  hive)         echo "CREATE DATABASE lake ENGINE = DataLakeCatalog('thrift://hive-metastore:9083') SETTINGS catalog_type = 'hive', warehouse = 'hive', $S3" ;;
  unity)        echo "CREATE DATABASE lake ENGINE = DataLakeCatalog('http://unity-catalog:8080/api/2.1/unity-catalog') SETTINGS catalog_type = 'unity', use_unity_catalog_v2 = ${UNITY_V2:-1}, warehouse = 'lab', catalog_credential = 'unused-auth-disabled', region = 'us-east-1'${UEP:+, storage_endpoint = '$UEP'}" ;;
esac; }

PASS=0; FAIL=0; SUMMARY=()
check() { # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "    ok   $1 = $3"; return 0; fi
  echo "    FAIL $1: expected [$2] got [$3]"; return 1
}

if [ "$FAULT" = stop-catalog ]; then
  for c in "${CATALOGS[@]}"; do docker stop "$(container "$c")" >/dev/null; echo "fault: stopped $(container "$c")"; done
fi

for c in "${CATALOGS[@]}"; do
  echo "== $c"
  chq "DROP DATABASE IF EXISTS lake" >/dev/null
  ok=1; err=""
  out="$(chq "$(ddl "$c")")" || ok=0
  [ $ok = 1 ] && [ -n "$out" ] && { ok=0; }
  if [ $ok = 0 ]; then err="CREATE DATABASE: $out"; fi
  if [ $ok = 1 ]; then
    t="$(chq "SHOW TABLES FROM lake")";                                            check "SHOW TABLES" "lab.events" "$t" || { ok=0; err="SHOW TABLES: $t"; }
    n="$(chq "SELECT count() FROM lake.\`lab.events\`")";                          check "count()" "5" "$n" || { ok=0; err="count: $n"; }
    s="$(chq "SELECT sum(id), round(sum(amount), 2) FROM lake.\`lab.events\`" | tr '\t' ' ')"; check "sum(id), sum(amount)" "15 152" "$s" || { ok=0; err="sum: $s"; }
    f="$(chq "SELECT name FROM lake.\`lab.events\` WHERE amount > 25 ORDER BY id" | paste -sd, -)"; check "WHERE amount > 25" "charlie,delta,echo" "$f" || { ok=0; err="filter: $f"; }
    v="$(chq "SELECT toString(ts) FROM lake.\`lab.events\` WHERE id = 3" )";       check "ts of id=3" "2026-11-04 03:00:00.000000" "$v" || { ok=0; err="ts: $v"; }
    ty="$(chq "SELECT toTypeName(id), toTypeName(amount), toTypeName(ts) FROM lake.\`lab.events\` LIMIT 1" | tr '\t' ' ')"; echo "    types: $ty"
  else
    echo "    $err" | cut -c1-600
  fi
  if [ $ok = 1 ]; then PASS=$((PASS+1)); SUMMARY+=("PASS  $c  5/5 rows"); else FAIL=$((FAIL+1)); SUMMARY+=("FAIL  $c  ${err:0:200}"); fi
  chq "DROP DATABASE IF EXISTS lake" >/dev/null
done

echo
echo "== Summary (ClickHouse $VERSION, fault: $FAULT)"
printf '  %s\n' "${SUMMARY[@]}"
echo "  $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
