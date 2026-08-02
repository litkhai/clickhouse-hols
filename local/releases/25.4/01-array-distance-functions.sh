#!/bin/bash

echo "================================"
echo "ClickHouse 25.4: Array Distance and Similarity Functions Test"
echo "================================"
echo ""

cat 01-array-distance-functions.sql | docker exec -i clickhouse-25-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
