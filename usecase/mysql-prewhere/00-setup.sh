#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== MySQL PREWHERE Test Environment Setup ===${NC}\n"

# ClickHouse connection settings
CH_HOST="localhost"
CH_PORT="9000"
CH_USER="default"
CH_PASSWORD=""
CH_MYSQL_PORT="9004"
CH_CLIENT="docker exec clickhouse-test clickhouse-client"

# Create database and table
echo -e "${GREEN}Creating test database and table...${NC}"
$CH_CLIENT --query="
DROP TABLE IF EXISTS default.prewhere_test;
DROP TABLE IF EXISTS default.prewhere_test_large;

CREATE TABLE default.prewhere_test
(
    id UInt64,
    date Date,
    timestamp DateTime,
    user_id UInt32,
    status String,
    value Float64,
    category LowCardinality(String),
    description String
)
ENGINE = MergeTree()
ORDER BY (date, user_id)
PARTITION BY toYYYYMM(date)
SETTINGS index_granularity = 8192;
"

echo -e "${GREEN}Inserting test data...${NC}"

# Insert sample data (1 million rows)
$CH_CLIENT --query="
INSERT INTO default.prewhere_test
SELECT
    number as id,
    toDate('2024-01-01') + toIntervalDay(number % 365) as date,
    toDateTime('2024-01-01 00:00:00') + toIntervalSecond(number) as timestamp,
    number % 100000 as user_id,
    if(number % 10 < 8, 'active', 'inactive') as status,
    rand() % 1000 + (number % 100) as value,
    arrayElement(['A', 'B', 'C', 'D', 'E'], (number % 5) + 1) as category,
    concat('Description for record ', toString(number)) as description
FROM numbers(1000000);
"

# Create larger table for performance testing
echo -e "${GREEN}Creating larger test table (10M rows)...${NC}"
$CH_CLIENT --query="
CREATE TABLE default.prewhere_test_large
(
    id UInt64,
    date Date,
    timestamp DateTime,
    user_id UInt32,
    status String,
    value Float64,
    category LowCardinality(String),
    description String,
    long_text String
)
ENGINE = MergeTree()
ORDER BY (date, user_id)
PARTITION BY toYYYYMM(date)
SETTINGS index_granularity = 8192;
"

$CH_CLIENT --query="
INSERT INTO default.prewhere_test_large
SELECT
    number as id,
    toDate('2024-01-01') + toIntervalDay(number % 365) as date,
    toDateTime('2024-01-01 00:00:00') + toIntervalSecond(number) as timestamp,
    number % 100000 as user_id,
    if(number % 10 < 8, 'active', 'inactive') as status,
    rand() % 1000 + (number % 100) as value,
    arrayElement(['A', 'B', 'C', 'D', 'E'], (number % 5) + 1) as category,
    concat('Description for record ', toString(number)) as description,
    repeat(concat('Long text content ', toString(number), ' '), 50) as long_text
FROM numbers(10000000);
"

echo -e "${GREEN}Optimizing tables...${NC}"
$CH_CLIENT --query="
OPTIMIZE TABLE default.prewhere_test FINAL;
OPTIMIZE TABLE default.prewhere_test_large FINAL;
"

# Verify data
echo -e "\n${BLUE}=== Data Summary ===${NC}"
$CH_CLIENT --query="
SELECT
    'prewhere_test' as table,
    count() as total_rows,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'default' AND table = 'prewhere_test' AND active
UNION ALL
SELECT
    'prewhere_test_large' as table,
    count() as total_rows,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'default' AND table = 'prewhere_test_large' AND active;
" --format=PrettyCompact

echo -e "\n${GREEN}Row counts:${NC}"
$CH_CLIENT --query="
SELECT 'prewhere_test' as table, count() as rows FROM default.prewhere_test
UNION ALL
SELECT 'prewhere_test_large' as table, count() as rows FROM default.prewhere_test_large;
" --format=PrettyCompact

echo -e "\n${BLUE}=== Connection Information ===${NC}"
echo -e "ClickHouse Native: ${GREEN}clickhouse-client --host=$CH_HOST --port=$CH_PORT${NC}"
echo -e "MySQL Protocol: ${GREEN}mysql -h $CH_HOST -P $CH_MYSQL_PORT -u $CH_USER${NC}"

echo -e "\n${GREEN}✅ Setup complete!${NC}"
