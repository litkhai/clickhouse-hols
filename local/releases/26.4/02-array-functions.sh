#!/bin/bash

echo "================================"
echo "ClickHouse 26.4: arrayTranspose + arrayAutocorrelation Test"
echo "================================"
echo ""

cat 02-array-functions.sql | docker exec -i clickhouse-26-4 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
