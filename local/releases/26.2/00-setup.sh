#!/bin/bash

# ClickHouse 26.2 Setup Script
# Purpose: Deploy ClickHouse 26.2 using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-mac-setup"

echo "🚀 ClickHouse 26.2 Setup"
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

# Run setup with version 26.2 (single version uses default ports)
echo "📦 Setting up ClickHouse version 26.2..."
./set.sh 26.2

echo ""
echo "▶️  Starting ClickHouse 26.2..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation (uses default port 8123)
echo ""
echo "✅ Verifying ClickHouse 26.2 installation..."
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
echo "✅ ClickHouse 26.2 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   Run feature test scripts in order:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-primes-function.sh"
echo "   ./02-xxh3-128-hash.sh"
echo "   ./03-system-tokenizers.sh"
echo ""
