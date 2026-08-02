#!/bin/bash

echo "================================"
echo "ClickHouse 25.4: toInterval and Database Comments Test"
echo "================================"
echo ""

cat 03-tointerval-and-db-comments.sql | docker exec -i clickhouse-25-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
