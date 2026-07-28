#!/bin/bash

echo "================================"
echo "ClickHouse 26.7: groupFormat + -Tuple Combinator Test"
echo "================================"
echo ""

cat 03-groupformat-tuple.sql | docker exec -i clickhouse-26-7 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
