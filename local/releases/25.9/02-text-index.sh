#!/bin/bash

# ClickHouse 25.9 Feature Test: New Text Index (Full-Text Search)
# Purpose: Test experimental full-text search capabilities

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-text-index.sql"
CLICKHOUSE_HTTP="http://localhost:2509"

echo "📝 ClickHouse 25.9 Feature: Text Index (Full-Text Search)"
echo "=========================================================="
echo ""

# Check if ClickHouse is running
if ! curl -sf "$CLICKHOUSE_HTTP" > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2509"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

echo "📝 Executing text index tests..."
echo ""

# Execute SQL file
cat "$SQL_FILE" | docker exec -i clickhouse-25-9 clickhouse-client --multiquery

echo ""
echo "✅ Text index test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Full-text index creation"
echo "   ✓ Basic text search queries"
echo "   ✓ Multi-term search"
echo "   ✓ Category and time-based searches"
echo "   ✓ Complex search patterns"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-09"
echo ""
