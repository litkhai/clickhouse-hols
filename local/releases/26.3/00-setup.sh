#!/bin/bash

# ClickHouse 26.3 LTS Setup Script
# Purpose: Deploy ClickHouse 26.3 LTS using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-mac-setup"

echo "🚀 ClickHouse 26.3 LTS Setup"
echo "=========================="
echo ""

if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

cd "$OSS_MAC_SETUP_DIR"

echo "📍 Using oss-mac-setup at: $OSS_MAC_SETUP_DIR"
echo ""
echo "📦 Setting up ClickHouse version 26.3..."
./set.sh 26.3

echo ""
echo "▶️  Starting ClickHouse 26.3..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

echo ""
echo "✅ Verifying ClickHouse 26.3 installation..."
VERSION_CHECK=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION_CHECK" ]; then
    echo "   ✅ $VERSION_CHECK"
else
    echo "   ⚠️  Could not verify version"
fi

echo ""
echo "📍 Connection Information:"
echo "   🌐 Web UI: http://localhost:8123/play"
echo "   📡 HTTP API: http://localhost:8123"
echo "   🔌 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   cd $OSS_MAC_SETUP_DIR"
echo "   ./status.sh          - Check status"
echo "   ./client.sh 8123     - Connect to CLI"
echo "   ./stop.sh            - Stop ClickHouse"
echo ""
echo "✅ ClickHouse 26.3 LTS setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-materialized-cte.sh"
echo "   ./02-natural-sort-key.sh"
echo "   ./03-unicode-functions.sh"
echo ""
