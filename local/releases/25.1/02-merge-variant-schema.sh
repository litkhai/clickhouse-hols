#!/bin/bash

echo "================================"
echo "ClickHouse 25.1: Merge Tables with Variant Schema Unification Test"
echo "================================"
echo ""

cat 02-merge-variant-schema.sql | docker exec -i clickhouse-25-1 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
