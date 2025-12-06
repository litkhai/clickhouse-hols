#!/bin/bash

# ClickHouse 25.6 Feature Test: lag and lead Window Functions
# Purpose: Test the new lag and lead window functions for SQL compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-lag-lead-functions.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "📊 ClickHouse 25.6 Feature: lag and lead Window Functions"
echo "=========================================================="
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
echo "📝 Executing lag/lead window functions tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery

echo ""
echo "✅ lag/lead window functions test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ lag() function for accessing previous rows"
echo "   ✓ lead() function for accessing next rows"
echo "   ✓ Window partitioning and ordering"
echo "   ✓ Time series analysis and trend detection"
echo "   ✓ Customer behavior and conversion tracking"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
