#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Resetting ClickHouse Tables"
echo "=========================================="

echo ""
echo "⚠️  This will DROP and recreate all tables!"
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "[1/3] Dropping existing tables..."

# Drop materialized views first
docker exec clickhouse clickhouse-client --query "DROP VIEW IF EXISTS default.buffer_to_mysql_mv"
docker exec clickhouse clickhouse-client --query "DROP VIEW IF EXISTS default.kafka_to_buffer_mv"

# Drop tables
docker exec clickhouse clickhouse-client --query "DROP TABLE IF EXISTS default.mysql_aggregated_events"
docker exec clickhouse clickhouse-client --query "DROP TABLE IF EXISTS default.events_buffer"
docker exec clickhouse clickhouse-client --query "DROP TABLE IF EXISTS default.kafka_events"

echo "✅ Tables dropped"

echo ""
echo "[2/3] Recreating tables..."

# Create Kafka source table
docker exec clickhouse clickhouse-client --query "
CREATE TABLE default.kafka_events (
    event_time DateTime DEFAULT now(),
    query_kind String,
    query_duration_ms UInt32
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'test-events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;
"

# Create buffer table
docker exec clickhouse clickhouse-client --query "
CREATE TABLE default.events_buffer (
    event_time DateTime,
    query_kind String,
    query_duration_ms UInt32
) ENGINE = MergeTree()
ORDER BY (event_time, query_kind);
"

# Create MySQL table engine
docker exec clickhouse clickhouse-client --query "
CREATE TABLE default.mysql_aggregated_events (
    event_date Date,
    query_kind String,
    query_count UInt64,
    total_duration_ms UInt64
) ENGINE = MySQL('mysql:3306', 'testdb', 'aggregated_events', 'clickhouse', 'clickhouse');
"

echo "✅ Tables created"

echo ""
echo "[3/3] Creating materialized views..."

# Kafka -> Buffer MView
docker exec clickhouse clickhouse-client --query "
CREATE MATERIALIZED VIEW default.kafka_to_buffer_mv
TO default.events_buffer
AS
SELECT
    event_time,
    query_kind,
    query_duration_ms
FROM default.kafka_events;
"

# Buffer -> MySQL MView with block size settings
docker exec clickhouse clickhouse-client --query "
CREATE MATERIALIZED VIEW default.buffer_to_mysql_mv
TO default.mysql_aggregated_events
AS
SELECT
    toDate(event_time) AS event_date,
    query_kind,
    count() AS query_count,
    sum(query_duration_ms) AS total_duration_ms
FROM default.events_buffer
GROUP BY event_date, query_kind
SETTINGS
    max_block_size = 1000,
    min_insert_block_size_rows = 5000,
    min_insert_block_size_bytes = 268435456;
"

echo "✅ Materialized views created"

echo ""
echo "=========================================="
echo "✅ Tables reset completed!"
echo "=========================================="
