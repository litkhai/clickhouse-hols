#!/usr/bin/env bash
# 01-up.sh — bring up Kafka (KRaft) + ClickHouse + Kafka Connect, wait until healthy.
# First run builds the Connect image (installs the ClickHouse sink connector) — a
# few minutes; subsequent runs are instant.
set -euo pipefail
cd "$(dirname "$0")"
. ./_env.sh; load_env

echo "▶ Building Connect image (first run only) + starting Kafka, ClickHouse, Connect…"
docker compose up -d --build

echo "▶ Waiting for all three services to report healthy (Connect can take ~30-60s)…"
for i in $(seq 1 80); do
  k=$(docker inspect -f '{{.State.Health.Status}}' kpart-kafka 2>/dev/null || echo starting)
  c=$(docker inspect -f '{{.State.Health.Status}}' kpart-clickhouse 2>/dev/null || echo starting)
  n=$(docker inspect -f '{{.State.Health.Status}}' kpart-connect 2>/dev/null || echo starting)
  if [[ "$k" == "healthy" && "$c" == "healthy" && "$n" == "healthy" ]]; then
    echo "✅ kafka=$k  clickhouse=$c  connect=$n (after ~$((i*3))s)"
    break
  fi
  printf '  kafka=%-9s clickhouse=%-9s connect=%-9s\r' "$k" "$c" "$n"
  sleep 3
  if [[ $i -eq 80 ]]; then
    echo; echo "⚠ Timed out. Logs:  docker compose logs kafka clickhouse connect"; exit 1
  fi
done

cat <<EOF

────────────────────────────────────────────────────────────
  Kafka (host)      ${KAFKA_BOOTSTRAP:-localhost:9094}
  Kafka (internal)  kafka:9092           (used by ClickHouse + Connect)
  ClickHouse HTTP   http://localhost:${CLICKHOUSE_HTTP_PORT:-8124}
  ClickHouse native localhost:${CLICKHOUSE_NATIVE_PORT:-9001}
  Connect REST      http://localhost:${CONNECT_REST_PORT:-8083}

  Next:
    ./02-create-topics.sh
    docker compose exec -T clickhouse clickhouse-client --multiquery < 03-clickhouse-setup.sql
    ./04-register-connectors.sh
    python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
    python 05-produce.py
    docker compose exec -T clickhouse clickhouse-client --multiquery < 06-compare.sql
────────────────────────────────────────────────────────────
EOF
