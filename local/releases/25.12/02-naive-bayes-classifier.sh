#!/bin/bash

echo "================================"
echo "ClickHouse 25.12: Naive Bayes Classifier Test"
echo "================================"
echo ""

cat 02-naive-bayes-classifier.sql | docker exec -i clickhouse-25-12 clickhouse-client --multiline --multiquery

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
