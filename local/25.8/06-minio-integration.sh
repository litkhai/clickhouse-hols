#!/bin/bash

# ClickHouse 25.8 Feature Test: MinIO Integration
# Purpose: Test ClickHouse 25.8 with MinIO S3-compatible storage

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/06-minio-integration.sql"
CLICKHOUSE_HTTP="http://localhost:2508"
MINIO_ENDPOINT="http://localhost:19000"

echo "📦 ClickHouse 25.8 Feature: MinIO Integration"
echo "=============================================="
echo ""

# Check if ClickHouse is running
if ! curl -sf "$CLICKHOUSE_HTTP" > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2508"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

# Check if MinIO is running
if ! curl -sf "$MINIO_ENDPOINT/minio/health/live" > /dev/null 2>&1; then
    echo "❌ MinIO is not running on port 19000"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo "✅ MinIO is running"
echo ""

echo "📝 Executing MinIO integration tests..."
echo ""

# Execute SQL file
cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiquery

echo ""
echo "✅ MinIO integration test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ S3 function with MinIO endpoint"
echo "   ✓ New Parquet reader (1.81x faster)"
echo "   ✓ Column pruning optimization"
echo "   ✓ Hive-style partitioning"
echo "   ✓ Data lake analytics queries"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
