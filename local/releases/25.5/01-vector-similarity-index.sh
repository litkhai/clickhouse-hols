#!/bin/bash

# ClickHouse 25.5 Feature Test: Vector Similarity Index (Beta)
# Purpose: Test the vector similarity index with pre/post-filtering and rescoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/01-vector-similarity-index.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-docker"

echo "🔍 ClickHouse 25.5 Feature: Vector Similarity Index (Beta)"
echo "=========================================================="
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
echo "📝 Executing Vector Similarity Index tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Vector Similarity Index test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ HNSW vector index creation"
echo "   ✓ L2Distance similarity search"
echo "   ✓ Prefiltering strategy"
echo "   ✓ Postfiltering strategy"
echo "   ✓ Hybrid search with metadata filters"
echo "   ✓ Product recommendation use case"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-05"
