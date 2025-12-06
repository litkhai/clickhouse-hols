#!/bin/bash

# ClickHouse 25.8 Setup Script
# Purpose: Deploy ClickHouse 25.8 using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🚀 ClickHouse 25.8 Setup"
echo "=========================="
echo ""

# Check if oss-mac-setup exists
if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

# Navigate to oss-mac-setup directory
cd "$OSS_MAC_SETUP_DIR"

echo "📍 Using oss-mac-setup at: $OSS_MAC_SETUP_DIR"
echo ""

# Run setup with version 25.8
echo "📦 Setting up ClickHouse version 25.8..."
./set.sh 25.8

echo ""
echo "▶️  Starting ClickHouse 25.8..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation
echo ""
echo "✅ Verifying ClickHouse 25.8 installation..."
VERSION_CHECK=$(curl -s http://localhost:2508/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION_CHECK" ]; then
    echo "   ✅ $VERSION_CHECK"
else
    echo "   ⚠️  Could not verify version"
fi

echo ""
echo "📍 Connection Information:"
echo "   🌐 Web UI: http://localhost:2508/play"
echo "   📡 HTTP API: http://localhost:2508"
echo "   🔌 TCP: localhost:25081"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   cd $OSS_MAC_SETUP_DIR"
echo "   ./status.sh          - Check status"
echo "   ./client.sh 2508     - Connect to CLI"
echo "   ./stop.sh            - Stop ClickHouse"
echo ""
echo "✅ ClickHouse 25.8 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   Run feature test scripts in order:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-new-parquet-reader.sh"
echo "   ./02-hive-partitioning.sh"
echo "   ./03-temp-data-s3.sh"
echo "   ./04-union-all-table.sh"
echo "   ./05-data-lake-features.sh"
echo ""
