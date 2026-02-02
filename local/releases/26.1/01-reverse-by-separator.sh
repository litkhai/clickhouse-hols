#!/bin/bash

echo "================================"
echo "ClickHouse 26.1: reverseBySeparator Function Test"
echo "================================"
echo ""

cat 01-reverse-by-separator.sql | docker exec -i clickhouse-26-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
