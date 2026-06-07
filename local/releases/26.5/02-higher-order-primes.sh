#!/bin/bash

echo "================================"
echo "ClickHouse 26.5: Bare Function Names + isPrime/isProbablePrime Test"
echo "================================"
echo ""

cat 02-higher-order-primes.sql | docker exec -i clickhouse-26-5 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
