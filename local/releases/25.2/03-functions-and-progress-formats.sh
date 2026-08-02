#!/bin/bash

echo "================================"
echo "ClickHouse 25.2: stringCompare, initialQueryStartTime and Progress Formats Test"
echo "================================"
echo ""

cat 03-functions-and-progress-formats.sql | docker exec -i clickhouse-25-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
