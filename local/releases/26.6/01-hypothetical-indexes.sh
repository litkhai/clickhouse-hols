#!/bin/bash

echo "================================"
echo "ClickHouse 26.6: Hypothetical Indexes + EXPLAIN WHATIF Test"
echo "================================"
echo ""

cat 01-hypothetical-indexes.sql | docker exec -i clickhouse-26-6 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
