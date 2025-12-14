#!/bin/bash

echo "================================"
echo "ClickHouse 25.11: Fractional LIMIT Test"
echo "================================"
echo ""

cat 02-fractional-limit.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
