#!/bin/bash

echo "================================"
echo "ClickHouse 26.8: Pipe operators (|>) Test"
echo "================================"
echo ""

cat 01-pipe-operators.sql | docker exec -i clickhouse-26-8 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
