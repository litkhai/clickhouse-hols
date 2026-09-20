#!/bin/bash

# ClickHouse TimeSeries + PromQL lab — OSS setup
#
# Both features are experimental and change fast (see README "Gotchas"),
# so this lab pins a specific, verified version rather than "latest".

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../local/oss-mac-setup"
VERSION="26.8"

echo "🚀 ClickHouse TimeSeries + PromQL lab setup (OSS ${VERSION})"
echo "=============================================================="
echo ""

if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

cd "$OSS_MAC_SETUP_DIR"

echo "📦 Setting up ClickHouse version ${VERSION}..."
./set.sh "$VERSION"

echo ""
echo "▶️  Starting ClickHouse ${VERSION}..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

CONTAINER="clickhouse-${VERSION//./-}"

echo ""
echo "✅ Verifying ClickHouse ${VERSION} installation..."
docker exec -i "$CONTAINER" clickhouse-client --query "SELECT version()"

echo ""
echo "🔬 Checking that the experimental settings this lab needs actually exist..."
docker exec -i "$CONTAINER" clickhouse-client --query "
SELECT name, changed FROM system.settings
WHERE name IN (
    'allow_experimental_time_series_table',
    'allow_experimental_time_series_aggregate_functions'
)
FORMAT PrettyCompact
"

echo ""
echo "📍 Connection Information:"
echo "   🌐 Web UI: http://localhost:8123/play"
echo "   📡 HTTP API: http://localhost:8123"
echo "   🔌 TCP: localhost:9000 (container: $CONTAINER)"
echo "   👤 User: default (no password)"
echo ""
echo "🎯 Next Steps:"
echo "   cd $SCRIPT_DIR"
echo "   ./01-schema.sh"
echo "   ./02-load.sh"
echo "   ./03-promql-instant.sh"
echo "   ./04-promql-range.sh"
echo "   ./05-management.sh"
