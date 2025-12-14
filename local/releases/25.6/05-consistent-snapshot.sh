#!/bin/bash

# ClickHouse 25.6 Feature Test: Consistent Snapshot Across Queries
# Purpose: Test the consistent snapshot feature for multi-query consistency

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/05-consistent-snapshot.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "📸 ClickHouse 25.6 Feature: Consistent Snapshot Across Queries"
echo "=============================================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2506/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2506"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing consistent snapshot tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Consistent snapshot test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Snapshot isolation for read consistency"
echo "   ✓ Multi-query transactions with snapshot_id"
echo "   ✓ Preventing phantom reads during long operations"
echo "   ✓ Report generation with consistent data"
echo "   ✓ Audit and compliance scenarios"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
