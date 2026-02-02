#!/bin/bash

echo "================================"
echo "ClickHouse 26.1: Text Index for Array Columns Test"
echo "================================"
echo ""

cat 02-text-index-arrays.sql | docker exec -i clickhouse-26-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
