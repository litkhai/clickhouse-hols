#!/bin/bash

# ClickHouse 25.5 Feature Test: Implicit Table in clickhouse-local
# Purpose: Test the implicit table feature for simplified data exploration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-implicit-table.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "📊 ClickHouse 25.5 Feature: Implicit Table in clickhouse-local"
echo "=============================================================="
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
echo "📝 Executing Implicit Table tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Implicit Table test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Implicit table with JSONAllPathsWithTypes()"
echo "   ✓ Schema inference from JSON data"
echo "   ✓ Simplified data exploration patterns"
echo "   ✓ Quick data inspection without explicit FROM"
echo "   ✓ Streaming data analysis use cases"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-05"
