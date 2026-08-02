#!/bin/bash

echo "================================"
echo "ClickHouse 25.1: Automatic MinMax Indices Test"
echo "================================"
echo ""

cat 01-auto-minmax-index.sql | docker exec -i clickhouse-25-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
