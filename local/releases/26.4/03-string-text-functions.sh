#!/bin/bash

echo "================================"
echo "ClickHouse 26.4: obfuscateQuery + highlight + printf Test"
echo "================================"
echo ""

cat 03-string-text-functions.sql | docker exec -i clickhouse-26-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
