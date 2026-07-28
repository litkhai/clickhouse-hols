#!/bin/bash

# ClickHouse 25.9 Feature Test: arrayExcept Function
# Purpose: Test new array filtering function

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-array-except.sql"
CLICKHOUSE_HTTP="http://localhost:8123"

echo "🔧 ClickHouse 25.9 Feature: arrayExcept Function"
echo "================================================="
echo ""

# Check if ClickHouse is running
if ! curl -sf "$CLICKHOUSE_HTTP" > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 8123"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

echo "📝 Executing arrayExcept tests..."
echo ""

# Execute SQL file
cat "$SCRIPT_DIR/04-array-except.sql" | docker exec -i clickhouse-25-9 clickhouse-client --multiline --multiquery

echo ""
echo "✅ arrayExcept function test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Basic array filtering"
echo "   ✓ Permission management"
echo "   ✓ Feature filtering"
echo "   ✓ Tag management"
echo "   ✓ Security rules"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-09"
echo ""
