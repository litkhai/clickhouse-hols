#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Block Size Settings Validation Test"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to execute ClickHouse query
ch_query() {
    docker exec clickhouse clickhouse-client --query "$1" 2>/dev/null || echo "ERROR"
}

# Function to execute MySQL query
mysql_query() {
    docker exec mysql mysql -u clickhouse -pclickhouse testdb -e "$1" 2>/dev/null || echo "ERROR"
}

echo ""
echo -e "${BLUE}[1/6] Checking MView settings in system.tables...${NC}"
echo ""

SETTINGS_CHECK=$(ch_query "
SELECT
    name,
    extractKeyValuePairs(create_table_query, 'SETTINGS') as settings_text,
    if(settings_text LIKE '%min_insert_block_size_rows%', '✅', '❌') as has_min_insert,
    if(settings_text LIKE '%max_block_size%', '✅', '❌') as has_max_block
FROM system.tables
WHERE name = 'buffer_to_mysql_mv' AND database = 'default'
FORMAT Vertical
")

echo "$SETTINGS_CHECK"

echo ""
echo -e "${BLUE}[2/6] Checking detailed MView SETTINGS...${NC}"
echo ""

SETTINGS_DETAIL=$(ch_query "
SELECT
    name,
    engine,
    create_table_query
FROM system.tables
WHERE name = 'buffer_to_mysql_mv' AND database = 'default'
FORMAT Vertical
")

echo "$SETTINGS_DETAIL"

echo ""
echo -e "${BLUE}[3/6] Installing Python dependencies for Kafka producer...${NC}"
echo ""

# Check if kafka-python is installed
if ! python3 -c "import kafka" 2>/dev/null; then
    echo "Installing kafka-python..."
    pip3 install kafka-python --quiet
    echo "✅ kafka-python installed"
else
    echo "✅ kafka-python already installed"
fi

echo ""
echo -e "${BLUE}[4/6] Clearing existing data...${NC}"
echo ""

# Clear MySQL table
mysql_query "TRUNCATE TABLE testdb.aggregated_events"
echo "✅ MySQL table cleared"

# Clear ClickHouse buffer
ch_query "TRUNCATE TABLE default.events_buffer"
echo "✅ ClickHouse buffer cleared"

echo ""
echo -e "${BLUE}[5/6] Producing test events to Kafka...${NC}"
echo ""
echo "Sending 50,000 events to Kafka topic 'test-events'..."
echo "This will test if min_insert_block_size_rows=5000 is applied"
echo ""

python3 scripts/kafka_producer.py \
    --bootstrap-servers localhost:9092 \
    --topic test-events \
    --num-events 50000 \
    --batch-size 500

echo ""
echo -e "${YELLOW}⏳ Waiting for data to be processed (30 seconds)...${NC}"
sleep 30

echo ""
echo -e "${BLUE}[6/6] Validating results...${NC}"
echo ""

# Check ClickHouse buffer
echo "📊 ClickHouse Buffer Table (events_buffer):"
BUFFER_COUNT=$(ch_query "SELECT count() FROM default.events_buffer")
echo "  Total rows: $BUFFER_COUNT"

echo ""
echo "📊 ClickHouse MySQL Engine Table (mysql_aggregated_events):"
MYSQL_ENGINE_RESULT=$(ch_query "
SELECT
    event_date,
    query_kind,
    query_count,
    total_duration_ms
FROM default.mysql_aggregated_events
ORDER BY event_date, query_kind
FORMAT PrettyCompact
")
echo "$MYSQL_ENGINE_RESULT"

echo ""
echo "📊 MySQL Direct Query (aggregated_events):"
MYSQL_RESULT=$(mysql_query "
SELECT
    event_date,
    query_kind,
    query_count,
    total_duration_ms,
    last_updated
FROM testdb.aggregated_events
ORDER BY event_date, query_kind;
" 2>&1 | grep -v "Warning")
echo "$MYSQL_RESULT"

echo ""
echo "📊 Checking query_log for MView execution..."
QUERY_LOG=$(ch_query "
SELECT
    event_time,
    query_kind,
    query,
    Settings['max_block_size'] AS max_block_size,
    Settings['min_insert_block_size_rows'] AS min_insert_block_size_rows,
    read_rows,
    written_rows
FROM system.query_log
WHERE
    query LIKE '%buffer_to_mysql_mv%'
    AND event_time > now() - INTERVAL 5 MINUTE
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5
FORMAT Vertical
")

if [ -n "$QUERY_LOG" ] && [ "$QUERY_LOG" != "ERROR" ]; then
    echo "$QUERY_LOG"
else
    echo "⚠️  No recent query_log entries found for the MView"
fi

echo ""
echo "=========================================="
echo "✅ Test completed!"
echo "=========================================="
echo ""
echo "Analysis:"
echo "  1. Check if min_insert_block_size_rows (5000) is visible in system.tables"
echo "  2. Verify data flow: Kafka → events_buffer → MySQL"
echo "  3. Check query_log for actual block sizes used during INSERT"
echo ""
echo "Expected behavior:"
echo "  - MView should accumulate at least 5000 rows before inserting to MySQL"
echo "  - max_block_size=1000 limits read block size from source"
echo "  - min_insert_block_size_rows=5000 controls batch size to MySQL"
echo ""
