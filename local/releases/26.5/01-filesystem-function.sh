#!/bin/bash

echo "================================"
echo "ClickHouse 26.5: filesystem Table Function Test"
echo "================================"
echo ""

cat 01-filesystem-function.sql | docker exec -i clickhouse-26-5 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
