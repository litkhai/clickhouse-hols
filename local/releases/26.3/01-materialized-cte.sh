#!/bin/bash

echo "================================"
echo "ClickHouse 26.3: Materialized CTE Test"
echo "================================"
echo ""

cat 01-materialized-cte.sql | docker exec -i clickhouse-26-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
