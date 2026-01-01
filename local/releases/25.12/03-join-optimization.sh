#!/bin/bash

echo "================================"
echo "ClickHouse 25.12: JOIN Order Optimization (DPSize) Test"
echo "================================"
echo ""

cat 03-join-optimization.sql | docker exec -i clickhouse-25-12 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
