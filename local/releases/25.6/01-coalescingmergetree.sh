#!/bin/bash

# ClickHouse 25.6 Feature Test: CoalescingMergeTree Table Engine
# Purpose: Test the new CoalescingMergeTree engine optimized for sparse updates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-coalescingmergetree.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🔄 ClickHouse 25.6 Feature: CoalescingMergeTree"
echo "================================================"
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
echo "📝 Executing CoalescingMergeTree tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery

echo ""
echo "✅ CoalescingMergeTree test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ CoalescingMergeTree table engine creation"
echo "   ✓ Sign column handling for updates/deletes"
echo "   ✓ Automatic coalescing during merges"
echo "   ✓ Efficient sparse update patterns"
echo "   ✓ Real-time metric tracking use case"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
