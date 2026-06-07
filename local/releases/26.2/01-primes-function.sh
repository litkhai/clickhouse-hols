#!/bin/bash

echo "================================"
echo "ClickHouse 26.2: primes Table Function & system.primes Test"
echo "================================"
echo ""

cat 01-primes-function.sql | docker exec -i clickhouse-26-2 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
