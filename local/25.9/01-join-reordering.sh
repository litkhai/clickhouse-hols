#!/bin/bash

# ClickHouse 25.9 Feature Test: Automatic Global Join Reordering
# Purpose: Test automatic join reordering based on table statistics

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-join-reordering.sql"
CLICKHOUSE_HTTP="http://localhost:2509"

echo "🚀 ClickHouse 25.9 Feature: Automatic Join Reordering"
echo "======================================================"
echo ""

# Check if ClickHouse is running
if ! curl -sf "$CLICKHOUSE_HTTP" > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2509"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

echo "📝 Executing join reordering tests..."
echo ""

# Execute SQL file
cat "$SQL_FILE" | docker exec -i clickhouse-25-9 clickhouse-client --multiquery

echo ""
echo "✅ Join reordering test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Multi-way joins with different table sizes"
echo "   ✓ Automatic join order optimization"
echo "   ✓ Statistics-based decision making"
echo "   ✓ Complex 4-way join graphs"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-09"
echo ""
