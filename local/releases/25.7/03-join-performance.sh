#!/bin/bash

# ClickHouse 25.7 Feature Test: JOIN Performance Improvements
# Purpose: Test the improved JOIN operations (up to 1.8x speedups)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-join-performance.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🔗 ClickHouse 25.7 Feature: JOIN Performance Improvements"
echo "=========================================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 8123"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing JOIN performance tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery

echo ""
echo "✅ JOIN performance test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ INNER JOIN with large datasets (up to 1.8x faster)"
echo "   ✓ LEFT JOIN optimization"
echo "   ✓ Multi-table JOIN scenarios"
echo "   ✓ JOIN with GROUP BY aggregations"
echo "   ✓ Complex analytical JOIN queries"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
