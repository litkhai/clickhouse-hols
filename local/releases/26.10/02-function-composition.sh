#!/bin/bash

# The three rules in 02-function-composition.sql are easiest to learn from the
# errors they produce. Errors stop a .sql file, so they run here.

CH="docker exec -i clickhouse-26-10 clickhouse-client"

echo "================================"
echo "ClickHouse 26.10: function composition and placeholders Test"
echo "================================"
echo ""

cat 02-function-composition.sql | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 6. The rules, as errors ════════"
echo ""

refused "6a. _ * _ is two arguments, so arrayMap over one array rejects it" \
    "SELECT arrayMap(_ * _, [1, 2, 3])"

refused "6b. | is not bitwise OR" \
    "SELECT 5 | 3"

refused "6c. a variadic function cannot be composed by name" \
    "SELECT arrayMap(toString | length, [10, 200])"

refused "6d. inside a scope with a column named _, the placeholder is that column" \
    "SELECT arrayMap(plus(_, 1), [1]) FROM (SELECT 100 AS _)"

echo "================================"
echo "Test complete!"
echo "================================"
