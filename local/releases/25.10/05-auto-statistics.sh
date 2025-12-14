#!/bin/bash

# ClickHouse 25.10 Feature Test: Auto Statistics
# Purpose: Test automatic statistics collection for query optimization

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/05-auto-statistics.sql"

echo "📈 ClickHouse 25.10 Feature: Auto Statistics"
echo "============================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2510/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2510"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing Auto Statistics tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Auto Statistics test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Table-level auto statistics configuration"
echo "   ✓ Automatic collection of minmax, uniq, countmin statistics"
echo "   ✓ Statistics-driven JOIN reordering"
echo "   ✓ Query optimization with statistics"
echo "   ✓ Statistics metadata inspection"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-10"
