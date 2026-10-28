#!/bin/bash

# 01-lateral-join.sql covers what works. The forms LATERAL does not accept, and
# the error the new join replaced, are raised exceptions, which would stop a .sql
# file at that line, so they run here, one statement per connection.

CH="docker exec -i clickhouse-26-10 clickhouse-client"

echo "================================"
echo "ClickHouse 26.10: LATERAL JOIN and arbitrary ON Test"
echo "================================"
echo ""

cat 01-lateral-join.sql | $CH --multiline --multiquery

refused() {
    echo "-- $1"
    $CH -q "$2" 2>&1 | grep -o 'Code: [0-9]*\..*' | head -1
    echo ""
}

echo ""
echo "════════ 6. What LATERAL refuses ════════"
echo ""

LAT="SET allow_experimental_lateral_join = 1;"

refused "6a. without the setting" \
    "SELECT c.name FROM lj.customers AS c LEFT JOIN LATERAL (SELECT id FROM lj.orders AS o WHERE o.customer_id = c.id) AS t ON true"

refused "6b. the comma form (FROM a, LATERAL (...)) is a syntax error" \
    "$LAT SELECT c.name FROM lj.customers AS c, LATERAL (SELECT id FROM lj.orders AS o WHERE o.customer_id = c.id) AS t"

refused "6c. so is CROSS JOIN LATERAL — write LEFT or INNER JOIN LATERAL ... ON true" \
    "$LAT SELECT c.name FROM lj.customers AS c CROSS JOIN LATERAL (SELECT id FROM lj.orders AS o WHERE o.customer_id = c.id) AS t"

refused "6d. a subquery that does not refer to the left side" \
    "$LAT SELECT c.name FROM lj.customers AS c LEFT JOIN LATERAL (SELECT 1 AS x) AS t ON true"

refused "6e. LIMIT ... WITH TIES has no LIMIT BY to decorrelate into" \
    "$LAT SELECT c.name FROM lj.customers AS c LEFT JOIN LATERAL (SELECT id FROM lj.orders AS o WHERE o.customer_id = c.id ORDER BY amount DESC LIMIT 1 WITH TIES) AS t ON true"

echo "════════ 7. The error 26.9 gave, with the new join switched off ════════"
echo ""

refused "7a. allow_block_nested_loop_join = 0: Code 403, now with a hint" \
    "SELECT count() FROM lj.orders AS o LEFT JOIN lj.bands AS b ON abs(toInt64(o.amount) - toInt64(b.lo)) < 10 SETTINGS allow_block_nested_loop_join = 0"

echo "================================"
echo "Test complete!"
echo "================================"
