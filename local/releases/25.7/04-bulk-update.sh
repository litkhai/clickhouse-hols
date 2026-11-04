#!/bin/bash

# 04-bulk-update.sql covers what works and prints the measured time and bytes.
# The refusals are raised exceptions, which would stop a .sql file at that line,
# so they run here, one statement per connection. Messages were read from 25.7.8.71.
#
# Container: CH_CONTAINER (default clickhouse-25-7, the one 00-setup.sh starts).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${CH_CONTAINER:-clickhouse-25-7}"
CH="docker exec -i $NAME clickhouse-client"

echo "================================"
echo "ClickHouse 25.7: Bulk UPDATE (patch parts) Test"
echo "================================"
echo ""

if ! $CH -q "SELECT 1" > /dev/null 2>&1; then
    echo "ClickHouse container $NAME is not reachable."
    echo "Start it with ./00-setup.sh, or set CH_CONTAINER to a running 25.7 container."
    exit 1
fi

cat "$SCRIPT_DIR/04-bulk-update.sql" | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 5. What a bulk UPDATE refuses (on products_patch from the .sql above) ════════"
echo ""

LU="SET allow_experimental_lightweight_update = 1;"

refused "5a. an ORDER BY key column (Code 420 CANNOT_UPDATE_COLUMN)" \
    "$LU UPDATE products_patch SET product_id = product_id + 1 WHERE category = 'Books'"

refused "5b. no WHERE clause (Code 62 SYNTAX_ERROR; write WHERE 1 for every row)" \
    "$LU UPDATE products_patch SET is_active = 1"

$CH --multiquery -q "DROP TABLE IF EXISTS products_plain; CREATE TABLE products_plain (product_id UInt64, is_active UInt8) ENGINE = MergeTree ORDER BY product_id; INSERT INTO products_plain SELECT number, 1 FROM numbers(1000);"

refused "5c. a table without enable_block_number_column / enable_block_offset_column (Code 48 NOT_IMPLEMENTED)" \
    "$LU UPDATE products_plain SET is_active = 0 WHERE product_id < 10"

$CH -q "DROP TABLE products_plain"

echo "================================"
echo "Test complete!"
echo "================================"
echo "Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
