#!/bin/bash

echo "================================"
echo "ClickHouse 25.1: New Functions Test"
echo "================================"
echo ""

cat 03-new-functions.sql | docker exec -i clickhouse-25-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
