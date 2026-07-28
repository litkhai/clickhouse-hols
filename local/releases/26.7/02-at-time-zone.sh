#!/bin/bash

echo "================================"
echo "ClickHouse 26.7: AT TIME ZONE / AT LOCAL Test"
echo "================================"
echo ""

cat 02-at-time-zone.sql | docker exec -i clickhouse-26-7 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
