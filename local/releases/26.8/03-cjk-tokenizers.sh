#!/bin/bash

echo "================================"
echo "ClickHouse 26.8: CJK / ICU tokenizers Test"
echo "================================"
echo ""

cat 03-cjk-tokenizers.sql | docker exec -i clickhouse-26-8 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
