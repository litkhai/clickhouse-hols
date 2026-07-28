#!/bin/bash

# ClickHouse 25.7 Feature Test: SQL UPDATE and DELETE Operations
# Purpose: Test the new lightweight UPDATE/DELETE with patch-part mechanism (up to 1000x faster)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-sql-update-delete.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.7 Feature: SQL UPDATE and DELETE Operations"
echo "============================================================="
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
echo "📝 Executing SQL UPDATE/DELETE tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery

echo ""
echo "✅ SQL UPDATE/DELETE test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Lightweight UPDATE operations with patch-part mechanism"
echo "   ✓ Lightweight DELETE operations (up to 1000x faster)"
echo "   ✓ UPDATE with WHERE conditions"
echo "   ✓ Bulk UPDATE performance comparison"
echo "   ✓ Real-world inventory update scenarios"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
