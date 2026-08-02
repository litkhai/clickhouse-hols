#!/bin/bash

echo "================================"
echo "ClickHouse 25.3 LTS: Query Condition Cache Test"
echo "================================"
echo ""

cat 02-query-condition-cache.sql | docker exec -i clickhouse-25-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
