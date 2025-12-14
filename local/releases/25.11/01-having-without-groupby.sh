#!/bin/bash

echo "================================"
echo "ClickHouse 25.11: HAVING without GROUP BY Test"
echo "================================"
echo ""

cat 01-having-without-groupby.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
