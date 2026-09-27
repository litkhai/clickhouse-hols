#!/bin/bash

# ClickHouse 25.5 Feature Test: Hive Metastore Catalog for Iceberg Tables
# Purpose: Test Hive metastore catalog support for querying Iceberg tables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-hive-metastore-catalog.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-docker"

echo "🗄️  ClickHouse 25.5 Feature: Hive Metastore Catalog"
echo "==================================================="
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
echo "📝 Executing Hive Metastore Catalog tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Hive Metastore Catalog test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ DataLakeCatalog table function usage"
echo "   ✓ Iceberg table format support"
echo "   ✓ Hive metastore Thrift protocol"
echo "   ✓ Lakehouse query patterns"
echo "   ✓ Integration with data lake architectures"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-05"
