#!/bin/bash

# ClickHouse 25.8 Feature Test: Enhanced UNION ALL with _table Virtual Column
# Purpose: Test UNION ALL with _table virtual column support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-union-all-table.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.8 Feature: Enhanced UNION ALL"
echo "=============================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2508/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2508"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing Enhanced UNION ALL tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Enhanced UNION ALL test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ UNION ALL with _table virtual column"
echo "   ✓ Identifying source table in merged results"
echo "   ✓ Multi-table union queries"
echo "   ✓ Data lineage tracking"
echo "   ✓ Filtering by source table"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
