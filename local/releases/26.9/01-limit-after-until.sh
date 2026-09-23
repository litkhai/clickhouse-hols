#!/bin/bash

echo "================================"
echo "ClickHouse 26.9: LIMIT ... AFTER / UNTIL Test"
echo "================================"
echo ""

cat 01-limit-after-until.sql | docker exec -i clickhouse-26-9 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
