#!/bin/bash

# ClickHouse 25.5 Feature Test: Geo Types in Parquet
# Purpose: Test enhanced Parquet reader for geographic data types

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/05-geo-types-parquet.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🌍 ClickHouse 25.5 Feature: Geo Types in Parquet"
echo "================================================="
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
echo "📝 Executing Geo Types in Parquet tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Geo Types in Parquet test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ WKB-encoded geometry parsing"
echo "   ✓ Point, LineString, Polygon types"
echo "   ✓ MultiPoint, MultiLineString, MultiPolygon"
echo "   ✓ GeoParquet dataset analysis"
echo "   ✓ Spatial query patterns"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-05"
