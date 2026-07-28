#!/bin/bash

# ClickHouse 25.10 Feature Test: QBit Data Type for Vector Search
# Purpose: Test the new QBit data type for enhanced vector search capabilities

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-qbit-vector-search.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🔍 ClickHouse 25.10 Feature: QBit Vector Search"
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
echo "📝 Executing QBit vector search tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-10 clickhouse-client --multiline --multiquery

echo ""
echo "✅ QBit Vector Search test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ QBit data type for vector embeddings"
echo "   ✓ L2 distance calculations"
echo "   ✓ Cosine distance calculations"
echo "   ✓ Similarity search operations"
echo "   ✓ Vector arithmetic operations"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-10"
