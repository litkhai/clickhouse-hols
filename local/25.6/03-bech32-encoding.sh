#!/bin/bash

# ClickHouse 25.6 Feature Test: Bech32 Encoding Functions
# Purpose: Test the new bech32Encode and bech32Decode functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/03-bech32-encoding.sql"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🔐 ClickHouse 25.6 Feature: Bech32 Encoding Functions"
echo "====================================================="
echo ""

# Check if ClickHouse is running
if ! curl -s http://localhost:2506/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse is not running on port 2506"
    echo "   Please run: cd $SCRIPT_DIR && ./00-setup.sh"
    exit 1
fi

echo "✅ ClickHouse is running"
echo ""

# Execute SQL file
echo "📝 Executing Bech32 encoding tests..."
echo ""

cat "$SQL_FILE" | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery

echo ""
echo "✅ Bech32 encoding test completed!"
echo ""
echo "📖 What was tested:"
echo "   ✓ bech32Encode function for encoding data"
echo "   ✓ bech32Decode function for decoding data"
echo "   ✓ Human-readable prefix (HRP) handling"
echo "   ✓ Cryptocurrency address encoding use case"
echo "   ✓ Error detection and checksum validation"
echo ""
echo "🔗 Reference: https://clickhouse.com/blog/clickhouse-release-25-06"
