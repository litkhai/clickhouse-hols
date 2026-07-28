#!/bin/bash

echo "================================"
echo "ClickHouse 26.7: EXPLAIN ANALYZE Test"
echo "================================"
echo ""

cat 01-explain-analyze.sql | docker exec -i clickhouse-26-7 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
