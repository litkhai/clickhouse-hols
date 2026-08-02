#!/bin/bash

echo "================================"
echo "ClickHouse 25.3 LTS: New Functions Test"
echo "================================"
echo ""

cat 01-new-functions.sql | docker exec -i clickhouse-25-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
