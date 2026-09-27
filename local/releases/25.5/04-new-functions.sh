#!/bin/bash

# ClickHouse 25.5 Feature Test: New Functions
# Purpose: Test new functions added in ClickHouse 25.5

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-new-functions.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-docker"

echo "🔧 ClickHouse 25.5 Feature: New Functions"
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
echo "📝 Executing New Functions tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery

echo ""
echo "✅ New Functions test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ sparseGrams() - substring extraction"
echo "   ✓ mapContainsKey() - map key checking"
echo "   ✓ mapContainsValue() - map value checking"
echo "   ✓ mapContainsValueLike() - map value pattern matching"
echo "   ✓ icebergHash() - Iceberg hashing function"
echo "   ✓ icebergBucketTransform() - Iceberg bucketing"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-05"
