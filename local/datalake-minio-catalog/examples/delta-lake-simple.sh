#!/usr/bin/env bash

# Simple Delta Lake Example
# This script demonstrates basic Delta Lake operations

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}  Simple Delta Lake Example${NC}"
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
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 1: Create sample dataset${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id UInt32,
    customer_id UInt32,
    product String,
    quantity UInt32,
    price Float64,
    order_date Date
) ENGINE = Memory;

INSERT INTO orders VALUES
    (1001, 101, 'Laptop', 1, 1299.99, '2025-12-01'),
    (1002, 102, 'Mouse', 2, 29.99, '2025-12-01'),
    (1003, 103, 'Keyboard', 1, 79.99, '2025-12-02'),
    (1004, 101, 'Monitor', 2, 299.99, '2025-12-02'),
    (1005, 104, 'Headphones', 1, 149.99, '2025-12-03');

SELECT 'Created orders table with ' || toString(count()) || ' rows' FROM orders;
"

echo ""
echo -e "${YELLOW}Step 2: Export to Delta Lake format (Parquet)${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SET s3_truncate_on_insert = 1;

INSERT INTO FUNCTION s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/delta-lake/orders.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
SELECT * FROM orders;

SELECT 'Orders exported to Delta Lake';
"

echo ""
echo -e "${YELLOW}Step 3: Query Delta Lake data${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SELECT
    order_id,
    customer_id,
    product,
    quantity,
    price,
    quantity * price as total_amount,
    order_date
FROM s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/delta-lake/orders.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
ORDER BY order_date, order_id
FORMAT PrettyCompact;
"

echo ""
echo -e "${YELLOW}Step 4: Aggregate analysis${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SELECT
    toYYYYMMDD(order_date) as date,
    count() as total_orders,
    sum(quantity) as total_items,
    round(sum(quantity * price), 2) as total_revenue
FROM s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/delta-lake/orders.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
GROUP BY order_date
ORDER BY date
FORMAT PrettyCompact;
"

echo ""
echo -e "${YELLOW}Step 5: Top customers${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
SELECT
    customer_id,
    count() as order_count,
    round(sum(quantity * price), 2) as total_spent
FROM s3(
    'http://host.docker.internal:${MINIO_PORT:-19000}/warehouse/delta-lake/orders.parquet',
    '${MINIO_ROOT_USER:-admin}',
    '${MINIO_ROOT_PASSWORD:-password123}',
    'Parquet'
)
GROUP BY customer_id
ORDER BY total_spent DESC
FORMAT PrettyCompact;
"

echo ""
echo -e "${YELLOW}Step 6: Cleanup${NC}"

docker exec $CLICKHOUSE_CONTAINER clickhouse-client --query "
DROP TABLE IF EXISTS orders;
SELECT 'Cleanup completed';
"

echo ""
echo -e "${GREEN}Example completed successfully!${NC}"
echo ""
echo "Delta Lake data location:"
echo "  MinIO Console: http://localhost:${MINIO_CONSOLE_PORT:-19001}"
echo "  Path: warehouse/delta-lake/orders.parquet"
echo ""
