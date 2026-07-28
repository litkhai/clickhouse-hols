#!/bin/bash

# ClickHouse 25.8 Feature Test: Temporary Data on S3
# Purpose: Test using S3 for temporary data instead of local disks only

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-temp-data-s3.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.8 Feature: Temporary Data on S3"
echo "================================================"
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
echo "📝 Executing Temporary Data on S3 tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Temporary Data on S3 test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Temporary data configuration for S3 storage"
echo "   ✓ Large JOIN operations with temp spillover"
echo "   ✓ Complex aggregations with temporary data"
echo "   ✓ Sorting operations using S3 temp storage"
echo "   ✓ Resource optimization scenarios"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
