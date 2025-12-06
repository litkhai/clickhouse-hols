#!/bin/bash

# ClickHouse 25.6 Setup Script
# Purpose: Deploy ClickHouse 25.6 using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../oss-mac-setup"

echo "🚀 ClickHouse 25.6 Setup"
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

# Run setup with version 25.6
echo "📦 Setting up ClickHouse version 25.6..."
./set.sh 25.6

echo ""
echo "▶️  Starting ClickHouse 25.6..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation
echo ""
echo "✅ Verifying ClickHouse 25.6 installation..."
VERSION_CHECK=$(curl -s http://localhost:2506/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION_CHECK" ]; then
    echo "   ✅ $VERSION_CHECK"
else
    echo "   ⚠️  Could not verify version"
fi

echo ""
echo "📍 Connection Information:"
echo "   🌐 Web UI: http://localhost:2506/play"
echo "   📡 HTTP API: http://localhost:2506"
echo "   🔌 TCP: localhost:25061"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   cd $OSS_MAC_SETUP_DIR"
echo "   ./status.sh          - Check status"
echo "   ./client.sh 2506     - Connect to CLI"
echo "   ./stop.sh            - Stop ClickHouse"
echo ""
echo "✅ ClickHouse 25.6 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   Run feature test scripts in order:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-coalescingmergetree.sh"
echo "   ./02-time-datatypes.sh"
echo "   ./03-bech32-encoding.sh"
echo "   ./04-lag-lead-functions.sh"
echo "   ./05-consistent-snapshot.sh"
