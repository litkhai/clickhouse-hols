#!/bin/bash

echo "================================"
echo "ClickHouse 25.11: Geometry Functions Test"
echo "================================"
echo ""

cat 04-geometry-functions.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
