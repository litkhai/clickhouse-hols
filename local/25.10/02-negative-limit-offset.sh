#!/bin/bash

# ClickHouse 25.10 Feature Test: Negative LIMIT and OFFSET
# Purpose: Test negative LIMIT and OFFSET support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-negative-limit-offset.sql"

echo "🔢 ClickHouse 25.10 Feature: Negative LIMIT/OFFSET"
echo "==================================================="
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
echo "📝 Executing Negative LIMIT/OFFSET tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Negative LIMIT/OFFSET test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Negative LIMIT for getting last N records"
echo "   ✓ Negative OFFSET for skipping from the end"
echo "   ✓ Combination of negative and positive values"
echo "   ✓ Practical use cases and pagination"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-10"
