#!/bin/bash

echo "================================"
echo "ClickHouse 26.8: GROUPS window frame mode Test"
echo "================================"
echo ""

cat 02-groups-window-frame.sql | docker exec -i clickhouse-26-8 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
