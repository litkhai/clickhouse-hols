#!/bin/bash

echo "================================"
echo "ClickHouse 26.5: tokenizeQuery + highlightQuery Test"
echo "================================"
echo ""

cat 03-tokenize-highlight-query.sql | docker exec -i clickhouse-26-5 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
