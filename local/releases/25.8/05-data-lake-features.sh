#!/bin/bash

# ClickHouse 25.8 Feature Test: Data Lake Enhancements
# Purpose: Test Iceberg/Delta Lake features including CREATE/DROP tables, writes, and time travel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/05-data-lake-features.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.8 Feature: Data Lake Enhancements"
echo "=================================================="
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
echo "📝 Executing Data Lake Enhancement tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Data Lake Enhancement test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ CREATE/DROP Iceberg tables"
echo "   ✓ Delta Lake write capabilities"
echo "   ✓ Time travel for versioned data"
echo "   ✓ Data lake table management"
echo "   ✓ Multi-format data lake integration"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
