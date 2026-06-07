#!/bin/bash

echo "================================"
echo "ClickHouse 26.3: naturalSortKey Function Test"
echo "================================"
echo ""

cat 02-natural-sort-key.sql | docker exec -i clickhouse-26-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
