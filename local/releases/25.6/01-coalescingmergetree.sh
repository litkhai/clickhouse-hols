#!/bin/bash

# 01-coalescingmergetree.sql covers what works. What CoalescingMergeTree refuses
# is a raised exception, which would stop a .sql file at that line, so it runs here,
# one statement per connection.
#
# Container: CH_CONTAINER (default clickhouse-25-6, the one 00-setup.sh starts).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${CH_CONTAINER:-clickhouse-25-6}"
CH="docker exec -i $NAME clickhouse-client"

echo "================================"
echo "ClickHouse 25.6: CoalescingMergeTree Test"
echo "================================"
echo ""

if ! $CH -q "SELECT 1" > /dev/null 2>&1; then
    echo "ClickHouse container $NAME is not reachable."
    echo "Start it with ./00-setup.sh, or set CH_CONTAINER to a running 25.6 container."
    exit 1
fi

cat "$SCRIPT_DIR/01-coalescingmergetree.sql" | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 6. What the engine parameter refuses ════════"
echo ""

refused "6a. a column that does not exist" \
    "CREATE TABLE device_bad (id UInt32, v Nullable(Int32)) ENGINE = CoalescingMergeTree(nope) ORDER BY id"

refused "6b. a sorting-key column in the list" \
    "CREATE TABLE device_bad (id UInt32, v Nullable(Int32)) ENGINE = CoalescingMergeTree(id) ORDER BY id"

refused "6c. something that is not a column name" \
    "CREATE TABLE device_bad (id UInt32, v Nullable(Int32)) ENGINE = CoalescingMergeTree(1) ORDER BY id"

echo "════════ 7. CoalescingMergeTree(Sign) is not a +1/-1 collapse ════════"
echo ""
echo "-- Sign is accepted, as the name of an ordinary column in the list. Rows with"
echo "-- Sign = 1 and Sign = -1 for one key do not cancel: one row is left."
$CH --multiquery -q "
DROP TABLE IF EXISTS device_sign;
CREATE TABLE device_sign (id UInt32, v Nullable(Int32), Sign Int8) ENGINE = CoalescingMergeTree(Sign) ORDER BY id;
INSERT INTO device_sign VALUES (1, 5, 1);
INSERT INTO device_sign VALUES (1, NULL, -1);
OPTIMIZE TABLE device_sign FINAL;
SELECT * FROM device_sign;
DROP TABLE device_sign;"
echo ""

echo "================================"
echo "Test complete!"
echo "================================"
echo "Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
