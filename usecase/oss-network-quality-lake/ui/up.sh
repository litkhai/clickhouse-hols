#!/usr/bin/env bash
# Local demo in one command: a ClickHouse container with its HTTP port published,
# the lab's SQL (01-03), then the demo server.  Stop with Ctrl-C; remove with
#   docker rm -f oss-lake-demo
set -euo pipefail
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="clickhouse/clickhouse-server:$(sed -n 's/^clickhouse: *//p' "$LAB/lab.yaml")"
NAME=oss-lake-demo
CH_PORT="${CH_PORT:-18123}"

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" --ulimit nofile=262144:262144 \
        -e CLICKHOUSE_PASSWORD= -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
        -p "127.0.0.1:$CH_PORT:8123" "$IMAGE" >/dev/null
    until docker exec "$NAME" clickhouse-client -q "SELECT 1" >/dev/null 2>&1; do sleep 1; done
    for f in 01-schema.sql 02-generate.sql 03-queries.sql; do
        echo "loading $f"
        docker exec -i "$NAME" clickhouse-client --multiquery < "$LAB/$f" >/dev/null
    done
fi
CH_URL="http://localhost:$CH_PORT" exec python3 "$LAB/ui/server.py"
