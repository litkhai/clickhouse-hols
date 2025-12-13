#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Service Status Check"
echo "=========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to execute ClickHouse query
ch_query() {
    docker exec clickhouse clickhouse-client --query "$1" 2>/dev/null || echo "ERROR"
}

# Function to execute MySQL query
mysql_query() {
    docker exec mysql mysql -u clickhouse -pclickhouse testdb -e "$1" 2>/dev/null || echo "ERROR"
}

echo ""
echo "🐳 Docker Containers:"
docker-compose ps

echo ""
echo "📊 ClickHouse Tables:"
TABLES=$(ch_query "
SELECT
    database,
    name,
    engine,
    total_rows
FROM system.tables
WHERE database = 'default'
    AND name IN ('kafka_events', 'events_buffer', 'mysql_aggregated_events', 'kafka_to_buffer_mv', 'buffer_to_mysql_mv')
ORDER BY name
FORMAT PrettyCompact
")
echo "$TABLES"

echo ""
echo "📊 MySQL Tables:"
MYSQL_TABLES=$(mysql_query "
SELECT
    TABLE_NAME,
    ENGINE,
    TABLE_ROWS,
    DATA_LENGTH
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'testdb'
ORDER BY TABLE_NAME;
" 2>&1 | grep -v "Warning")
echo "$MYSQL_TABLES"

echo ""
echo "📊 Data Counts:"
echo ""

# ClickHouse buffer
BUFFER_COUNT=$(ch_query "SELECT count() FROM default.events_buffer")
echo "  ClickHouse events_buffer: $BUFFER_COUNT rows"

# MySQL via ClickHouse engine
MYSQL_ENGINE_COUNT=$(ch_query "SELECT count() FROM default.mysql_aggregated_events")
echo "  MySQL (via ClickHouse): $MYSQL_ENGINE_COUNT rows"

# MySQL direct
MYSQL_DIRECT_COUNT=$(mysql_query "SELECT COUNT(*) FROM testdb.aggregated_events;" 2>&1 | grep -v "Warning" | tail -1)
echo "  MySQL (direct): $MYSQL_DIRECT_COUNT rows"

echo ""
echo "📊 Recent MySQL Data:"
MYSQL_DATA=$(mysql_query "
SELECT
    event_date,
    query_kind,
    query_count,
    total_duration_ms
FROM testdb.aggregated_events
ORDER BY event_date DESC, query_kind
LIMIT 10;
" 2>&1 | grep -v "Warning")
echo "$MYSQL_DATA"

echo ""
echo "📊 Kafka Topics:"
KAFKA_TOPICS=$(docker exec kafka kafka-topics --list --bootstrap-server localhost:29092 2>/dev/null || echo "ERROR")
echo "$KAFKA_TOPICS"

echo ""
echo "📊 Kafka Consumer Group:"
CONSUMER_GROUP=$(docker exec kafka kafka-consumer-groups --bootstrap-server localhost:29092 --group clickhouse_consumer --describe 2>/dev/null || echo "Consumer group not found or no data consumed yet")
echo "$CONSUMER_GROUP"

echo ""
echo "=========================================="
