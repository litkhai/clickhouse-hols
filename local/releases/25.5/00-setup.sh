#!/bin/bash

# ClickHouse 25.5 Setup Script
# Purpose: Deploy ClickHouse 25.5 using oss-docker and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-docker"

echo "🚀 ClickHouse 25.5 Setup"
echo "=========================="
echo ""

# Check if oss-docker exists
if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-docker directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

# Navigate to oss-docker directory
cd "$OSS_MAC_SETUP_DIR"

echo "📍 Using oss-docker at: $OSS_MAC_SETUP_DIR"
echo ""

# Run setup with version 25.5
echo "📦 Setting up ClickHouse version 25.5..."
./set.sh 25.5

echo ""
echo "▶️  Starting ClickHouse 25.5..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation (uses default port 8123)
echo ""
echo "✅ Verifying ClickHouse 25.5 installation..."
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
echo "✅ ClickHouse 25.5 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   Run feature test scripts in order:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-vector-similarity-index.sh"
echo "   ./02-hive-metastore-catalog.sh"
echo "   ./03-implicit-table.sh"
echo "   ./04-new-functions.sh"
echo "   ./05-geo-types-parquet.sh"
