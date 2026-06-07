#!/bin/bash

echo "================================"
echo "ClickHouse 26.2: xxh3_128 Hash Function Test"
echo "================================"
echo ""

cat 02-xxh3-128-hash.sql | docker exec -i clickhouse-26-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
