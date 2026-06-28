#!/usr/bin/env bash
# 04-register-connectors.sh — register the two ClickHouse Kafka Connect Sink
# connectors (PATH C). Each sinks one topic into one MergeTree table.
#
# Why Connect preserves partition locality "for free": the sink groups records
# by topic-partition and writes one batch per partition (ClickHouse connector
# design), so a range-partitioned topic yields contiguous-key parts without any
# ClickHouse-side tuning. We raise max.poll.records so batches (= parts) are
# larger and the part count stays sane with merges stopped.
set -euo pipefail
cd "$(dirname "$0")"
. ./_env.sh; load_env

REST="http://localhost:${CONNECT_REST_PORT:-8083}"
TASKS="${NUM_PARTITIONS:-8}"

register() {  # $1=name  $2=topic  $3=target_table
  echo "▶ registering connector '$1'  ($2 → kpart.$3)…"
  curl -fsS -X PUT -H "Content-Type: application/json" \
    "${REST}/connectors/$1/config" -d @- <<JSON >/dev/null
{
  "connector.class": "com.clickhouse.kafka.connect.ClickHouseSinkConnector",
  "tasks.max": "${TASKS}",
  "topics": "$2",
  "hostname": "clickhouse",
  "port": "8123",
  "database": "kpart",
  "username": "connect",
  "password": "connect",
  "ssl": "false",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "consumer.override.auto.offset.reset": "earliest",
  "consumer.override.max.poll.records": "50000",
  "consumer.override.fetch.max.bytes": "104857600",
  "consumer.override.max.partition.fetch.bytes": "104857600",
  "topic2TableMap": "$2=$3"
}
JSON
}

register clickhouse-aligned    events_aligned    connect_aligned
register clickhouse-misaligned events_misaligned connect_misaligned

echo "▶ waiting for tasks to reach RUNNING…"
for c in clickhouse-aligned clickhouse-misaligned; do
  for i in $(seq 1 20); do
    states=$(curl -fsS "${REST}/connectors/$c/status" \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print(','.join(t['state'] for t in d['tasks']) or 'NONE')")
    if [[ "$states" == RUNNING* && "$states" != *FAILED* && "$states" != *NONE* ]]; then
      echo "  $c: $states"; break
    fi
    sleep 3
    [[ $i -eq 20 ]] && { echo "  ⚠ $c not healthy: $states"; curl -fsS "${REST}/connectors/$c/status"; exit 1; }
  done
done
echo "✅ both connectors RUNNING. Now run: python 05-produce.py"
