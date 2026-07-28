#!/bin/bash

echo "================================"
echo "ClickHouse 26.6: SQL Compatibility and Ergonomics Test"
echo "================================"
echo ""

cat 03-sql-compatibility.sql | docker exec -i clickhouse-26-6 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
