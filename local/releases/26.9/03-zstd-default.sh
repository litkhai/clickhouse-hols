#!/bin/bash

echo "================================"
echo "ClickHouse 26.9: ZSTD(3) default compression Test"
echo "================================"
echo ""
echo "This one writes and merges about 26M rows, so give it a couple of minutes."
echo ""

cat 03-zstd-default.sql | docker exec -i clickhouse-26-9 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
