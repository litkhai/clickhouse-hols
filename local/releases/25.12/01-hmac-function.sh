#!/bin/bash

echo "================================"
echo "ClickHouse 25.12: HMAC Function Test"
echo "================================"
echo ""

cat 01-hmac-function.sql | docker exec -i clickhouse-25-12 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
