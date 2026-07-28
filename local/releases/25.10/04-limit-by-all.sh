#!/bin/bash

# ClickHouse 25.10 Feature Test: LIMIT BY ALL
# Purpose: Test new LIMIT BY ALL syntax for limiting duplicate records

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-limit-by-all.sql"

echo "📊 ClickHouse 25.10 Feature: LIMIT BY ALL"
echo "=========================================="
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
echo "📝 Executing LIMIT BY ALL tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery

echo ""
echo "✅ LIMIT BY ALL test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ LIMIT BY ALL syntax for limiting per group"
echo "   ✓ Multiple column combinations"
echo "   ✓ Data sampling and deduplication"
echo "   ✓ Session and event analysis use cases"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-10"
