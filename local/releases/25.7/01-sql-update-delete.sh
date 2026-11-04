#!/bin/bash

# 01-sql-update-delete.sql covers what works. The refusals are raised exceptions,
# which would stop a .sql file at that line, so they run here, one statement per
# connection. Messages below were read from 25.7.8.71.
#
# Container: CH_CONTAINER (default clickhouse-25-7, the one 00-setup.sh starts).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${CH_CONTAINER:-clickhouse-25-7}"
CH="docker exec -i $NAME clickhouse-client"

echo "================================"
echo "ClickHouse 25.7: SQL UPDATE (patch parts) and DELETE Test"
echo "================================"
echo ""

if ! $CH -q "SELECT 1" > /dev/null 2>&1; then
    echo "ClickHouse container $NAME is not reachable."
    echo "Start it with ./00-setup.sh, or set CH_CONTAINER to a running 25.7 container."
    exit 1
fi

cat "$SCRIPT_DIR/01-sql-update-delete.sql" | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 8. What UPDATE refuses ════════"
echo ""

$CH --multiquery -q "
DROP TABLE IF EXISTS inv_plain;
DROP TABLE IF EXISTS inv_half;
CREATE TABLE inv_plain (id UInt64, quantity UInt32) ENGINE = MergeTree ORDER BY id;
CREATE TABLE inv_half  (id UInt64, quantity UInt32) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1;
INSERT INTO inv_plain SELECT number, 1 FROM numbers(1000);
INSERT INTO inv_half  SELECT number, 1 FROM numbers(1000);"

refused "8a. UPDATE without allow_experimental_lightweight_update (Code 344 SUPPORT_IS_DISABLED)" \
    "UPDATE inv_plain SET quantity = 0 WHERE id < 10"

LU="SET allow_experimental_lightweight_update = 1;"

refused "8b. setting on, table without enable_block_number_column (Code 48 NOT_IMPLEMENTED)" \
    "$LU UPDATE inv_plain SET quantity = 0 WHERE id < 10"

refused "8c. enable_block_number_column only: it also asks for enable_block_offset_column (Code 48)" \
    "$LU UPDATE inv_half SET quantity = 0 WHERE id < 10"

echo "-- 8d. positive control: ALTER TABLE ... UPDATE needs none of this and works on inv_plain"
$CH --multiquery -q "ALTER TABLE inv_plain UPDATE quantity = 0 WHERE id < 10 SETTINGS mutations_sync = 2; SELECT countIf(quantity = 0) AS updated FROM inv_plain;"
echo ""

echo "-- 8e. positive control: after MODIFY SETTING on inv_half, the same UPDATE works"
$CH --multiquery -q "
ALTER TABLE inv_half MODIFY SETTING enable_block_offset_column = 1;
$LU UPDATE inv_half SET quantity = 0 WHERE id < 10;
SELECT countIf(quantity = 0) AS updated FROM inv_half;"
echo ""

$CH --multiquery -q "DROP TABLE inv_plain; DROP TABLE inv_half;"

echo "================================"
echo "Test complete!"
echo "================================"
echo "Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
