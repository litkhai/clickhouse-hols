#!/bin/bash

echo "================================"
echo "ClickHouse 25.2: Parquet Bloom Filters Test"
echo "================================"
echo ""

cat 01-parquet-bloom-filters.sql | docker exec -i clickhouse-25-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
