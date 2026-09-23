#!/bin/bash

echo "================================"
echo "ClickHouse 26.9: keyValuePairs text index tokenizer Test"
echo "================================"
echo ""

cat 02-keyvaluepairs-index.sql | docker exec -i clickhouse-26-9 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
