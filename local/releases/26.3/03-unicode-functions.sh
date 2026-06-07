#!/bin/bash

echo "================================"
echo "ClickHouse 26.3: Unicode Functions Test"
echo "================================"
echo ""

cat 03-unicode-functions.sql | docker exec -i clickhouse-26-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
