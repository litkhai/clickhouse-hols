#!/bin/bash

echo "================================"
echo "ClickHouse 26.6: ALTER TABLE ADD ENUM VALUES Test"
echo "================================"
echo ""

cat 02-add-enum-values.sql | docker exec -i clickhouse-26-6 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
