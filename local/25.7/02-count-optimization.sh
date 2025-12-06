#!/bin/bash

# ClickHouse 25.7 Feature Test: count() Aggregation Optimization
# Purpose: Test the optimized count() aggregation (20-30% faster, reduced memory)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-count-optimization.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🔢 ClickHouse 25.7 Feature: count() Aggregation Optimization"
echo "=============================================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2507/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2507"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing count() optimization tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery

echo ""
echo "✅ count() optimization test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Basic count() aggregation performance"
echo "   ✓ count() with GROUP BY (20-30% faster)"
echo "   ✓ count(DISTINCT) optimization"
echo "   ✓ Memory reduction in large aggregations"
echo "   ✓ Multi-dimensional counting scenarios"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
