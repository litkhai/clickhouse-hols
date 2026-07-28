#!/bin/bash

# ClickHouse 25.6 Feature Test: Time and Time64 Data Types
# Purpose: Test the new Time and Time64 data types for time-of-day representation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-time-datatypes.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⏰ ClickHouse 25.6 Feature: Time and Time64 Data Types"
echo "======================================================="
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
echo "📝 Executing Time data types tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Time data types test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Time data type for time-of-day representation"
echo "   ✓ Time64 data type for high-precision time values"
echo "   ✓ Time arithmetic and operations"
echo "   ✓ Business hours scheduling use case"
echo "   ✓ Performance monitoring and SLA tracking"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
