#!/bin/bash

echo "================================"
echo "ClickHouse 25.4: sparseGrams Test"
echo "================================"
echo ""

cat 02-sparsegrams.sql | docker exec -i clickhouse-25-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
