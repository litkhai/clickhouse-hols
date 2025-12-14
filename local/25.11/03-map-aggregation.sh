#!/bin/bash

echo "================================"
echo "ClickHouse 25.11: Map Aggregation Test"
echo "================================"
echo ""

cat 03-map-aggregation.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
