#!/bin/bash

echo "================================"
echo "ClickHouse 26.1: Keeper HTTP API Test"
echo "================================"
echo ""

cat 03-keeper-http-api.sql | docker exec -i clickhouse-26-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
