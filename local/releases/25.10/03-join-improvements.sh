#!/bin/bash

# ClickHouse 25.10 Feature Test: JOIN Improvements
# Purpose: Test lazy materialization, filter push-down, and automatic condition derivation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-join-improvements.sql"

echo "🔗 ClickHouse 25.10 Feature: JOIN Improvements"
echo "==============================================="
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
echo "📝 Executing JOIN improvements tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery

echo ""
echo "✅ JOIN Improvements test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Lazy materialization during JOIN operations"
echo "   ✓ Filter push-down (PREWHERE-like optimization)"
echo "   ✓ Automatic condition derivation for complex WHERE clauses"
echo "   ✓ Memory and CPU optimization for large JOINs"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-10"
