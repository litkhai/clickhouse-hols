#!/bin/bash

echo "================================"
echo "ClickHouse 25.3 LTS: estimateCompressionRatio Test"
echo "================================"
echo ""

cat 03-estimate-compression-ratio.sql | docker exec -i clickhouse-25-3 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
