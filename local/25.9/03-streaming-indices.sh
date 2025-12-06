#!/bin/bash

# ClickHouse 25.9 Feature Test: Streaming Secondary Indices
# Purpose: Test streaming indices for faster query startup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-streaming-indices.sql"
CLICKHOUSE_HTTP="http://localhost:2509"

echo "⚡ ClickHouse 25.9 Feature: Streaming Secondary Indices"
echo "========================================================"
echo ""

# Check if ClickHouse is running
if ! curl -sf "$CLICKHOUSE_HTTP" > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2509"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

echo "📝 Executing streaming indices tests..."
echo ""

# Execute SQL file
cat "$SQL_FILE" | docker exec -i clickhouse-25-9 clickhouse-client --multiquery

echo ""
echo "✅ Streaming indices test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Secondary index creation"
echo "   ✓ Streaming vs traditional index reading"
echo "   ✓ LIMIT query optimization"
echo "   ✓ Time-series and behavioral analysis"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-09"
echo ""
