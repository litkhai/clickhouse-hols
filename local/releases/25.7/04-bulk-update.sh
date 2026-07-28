#!/bin/bash

# ClickHouse 25.7 Feature Test: Bulk UPDATE Performance
# Purpose: Test bulk UPDATE operations (up to 4000x faster than PostgreSQL)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/04-bulk-update.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.7 Feature: Bulk UPDATE Performance"
echo "===================================================="
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
echo "📝 Executing bulk UPDATE performance tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Bulk UPDATE performance test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ Large-scale bulk UPDATE operations"
echo "   ✓ UPDATE with complex WHERE conditions"
echo "   ✓ Multi-column UPDATE scenarios"
echo "   ✓ Performance comparison (up to 4000x faster than PostgreSQL)"
echo "   ✓ Real-world ETL and data migration use cases"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-07"
