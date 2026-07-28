#!/bin/bash

# ClickHouse 25.8 Feature Test: New Parquet Reader
# Purpose: Test the new Parquet reader with 1.81x faster performance and 99.98% less data scanning

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-new-parquet-reader.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.8 Feature: New Parquet Reader"
echo "=============================================="
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
echo "📝 Executing New Parquet Reader tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery

echo ""
echo "✅ New Parquet Reader test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ New Parquet reader with 1.81x faster performance"
echo "   ✓ Efficient column pruning (99.98% less data scanned)"
echo "   ✓ Parquet file reading and querying"
echo "   ✓ Performance comparison scenarios"
echo "   ✓ Column-oriented data access optimization"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
