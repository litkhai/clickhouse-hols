#!/bin/bash

# ClickHouse 26.6 Setup Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-mac-setup"

echo "🚀 ClickHouse 26.6 Setup"
echo "=========================="
echo ""

if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

cd "$OSS_MAC_SETUP_DIR"

echo "📍 Using oss-mac-setup at: $OSS_MAC_SETUP_DIR"
echo ""
echo "📦 Setting up ClickHouse version 26.6..."
./set.sh 26.6

echo ""
echo "▶️  Starting ClickHouse 26.6..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

echo ""
echo "✅ Verifying ClickHouse 26.6 installation..."
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
echo "✅ ClickHouse 26.6 setup complete!"
echo ""
echo "🎯 Next Steps:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-hypothetical-indexes.sh"
echo "   ./02-add-enum-values.sh"
echo "   ./03-sql-compatibility.sh"
echo ""
