#!/bin/bash

# ClickHouse 25.9 Setup Script
# Purpose: Deploy ClickHouse 25.9 using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-mac-setup"

echo "🚀 ClickHouse 25.9 Setup"
echo "========================"
echo ""

# Check if directory exists
if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

# Setup ClickHouse
echo "📦 Setting up ClickHouse version 25.9..."
cd "$OSS_MAC_SETUP_DIR"
./set.sh 25.9

echo ""
echo "▶️  Starting ClickHouse 25.9..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation (uses default port 8123)
echo ""
echo "✅ Verifying ClickHouse 25.9 installation..."
VERSION_CHECK=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION_CHECK" ]; then
    echo "   ✅ $VERSION_CHECK"
else
    echo "   ⚠️  Could not verify version"
fi

echo ""
echo "📍 Connection Information:"
echo ""
echo "ClickHouse 25.9:"
echo "   🌐 Web UI: http://localhost:8123/play"
echo "   📡 HTTP API: http://localhost:8123"
echo "   🔌 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   cd $OSS_MAC_SETUP_DIR"
echo "   ./status.sh          - Check ClickHouse status"
echo "   ./client.sh 8123     - Connect to ClickHouse CLI"
echo "   ./stop.sh            - Stop ClickHouse"
echo ""
echo "✅ ClickHouse 25.9 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   Run feature test scripts in order:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-join-reordering.sh"
echo "   ./02-text-index.sh"
echo "   ./03-streaming-indices.sh"
echo "   ./04-s3-storage-class.sh"
echo "   ./04-array-except.sh"
echo ""
