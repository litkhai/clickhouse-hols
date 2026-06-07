#!/bin/bash

echo "================================"
echo "ClickHouse 26.4: NATURAL JOIN + VALUES Table Expression Test"
echo "================================"
echo ""

cat 01-natural-join-values.sql | docker exec -i clickhouse-26-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
