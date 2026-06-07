#!/bin/bash

echo "================================"
echo "ClickHouse 26.2: system.tokenizers Catalog Test"
echo "================================"
echo ""

cat 03-system-tokenizers.sql | docker exec -i clickhouse-26-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
