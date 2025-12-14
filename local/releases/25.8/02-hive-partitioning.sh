#!/bin/bash

# ClickHouse 25.8 Feature Test: Hive-Style Partitioning
# Purpose: Test hive-style partitioning with partition_strategy parameter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/02-hive-partitioning.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "⚡ ClickHouse 25.8 Feature: Hive-Style Partitioning"
echo "==================================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2508/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2508"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing Hive-Style Partitioning tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Hive-Style Partitioning test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ partition_strategy parameter for Hive-style layouts"
echo "   ✓ Directory-based partitioning (year=2024/month=12/)"
echo "   ✓ Writing data with Hive partitioning scheme"
echo "   ✓ Reading Hive-partitioned data efficiently"
echo "   ✓ Partition pruning optimization"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-08"
echo ""
