#!/usr/bin/env bash

# Basic S3 Read/Write Example
# This script demonstrates simple S3 operations with ClickHouse and MinIO

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  Basic S3 Read/Write Example${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.env"

# Check ClickHouse container
if docker ps | grep -q "clickhouse-25-1"; then
    CLICKHOUSE_CONTAINER=$(docker ps --format '{{.Names}}' | grep "clickhouse-25-1" | head -1)
    echo -e "${GREEN}Using ClickHouse container: $CLICKHOUSE_CONTAINER${NC}"
else
    echo -e "${YELLOW}No ClickHouse 25.10 or 25.11 container found${NC}"
    echo "Please start ClickHouse first"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 1: Create sample data${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
DROP TABLE IF EXISTS sample_data;
CREATE TABLE sample_data (
    id UInt32,
    name String,
    value Float64,
    created_at DateTime
) ENGINE = Memory;

INSERT INTO sample_data VALUES
    (1, 'Alice', 100.5, '2025-12-01 10:00:00'),
    (2, 'Bob', 200.7, '2025-12-02 11:30:00'),
    (3, 'Charlie', 150.3, '2025-12-03 09:15:00');

SELECT 'Created table with ' || toString(count()) || ' rows' FROM sample_data;
"

echo ""
echo -e "${YELLOW}Step 2: Write data to MinIO (S3)${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SET s3_truncate_on_insert = 1;

INSERT INTO FUNCTION s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/examples/sample-data.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
SELECT * FROM sample_data;

SELECT 'Data written to MinIO';
"

echo ""
echo -e "${YELLOW}Step 3: Read data back from MinIO${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SELECT
    id,
    name,
    value,
    created_at
FROM s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/examples/sample-data.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
FORMAT PrettyCompact;
"

echo ""
echo -e "${YELLOW}Step 4: Aggregate query on S3 data${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SELECT
    count() as total_rows,
    sum(value) as total_value,
    avg(value) as avg_value,
    min(created_at) as earliest,
    max(created_at) as latest
FROM s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/examples/sample-data.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
FORMAT Vertical;
"

echo ""
echo -e "${YELLOW}Step 5: Cleanup${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
DROP TABLE IF EXISTS sample_data;
SELECT 'Cleanup completed';
"

echo ""
echo -e "${GREEN}Example completed successfully!${NC}"
echo ""
echo "You can view the file in MinIO Console:"
echo "  URL: http://localhost:${MINIO_CONSOLE_PORT:-19001}"
echo "  Path: warehouse/examples/sample-data.parquet"
echo ""
