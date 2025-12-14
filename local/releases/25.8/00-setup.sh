#!/bin/bash

# ClickHouse 25.8 Setup Script
# Purpose: Deploy ClickHouse 25.8 using oss-mac-setup and verify installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSS_MAC_SETUP_DIR="$SCRIPT_DIR/../../oss-mac-setup"
DATALAKE_DIR="$SCRIPT_DIR/../datalake-minio-catalog"

echo "🚀 ClickHouse 25.8 Setup with Data Lake"
echo "========================================"
echo ""

# Check if directories exist
if [ ! -d "$OSS_MAC_SETUP_DIR" ]; then
    echo "❌ Error: oss-mac-setup directory not found at $OSS_MAC_SETUP_DIR"
    exit 1
fi

if [ ! -d "$DATALAKE_DIR" ]; then
    echo "❌ Error: datalake-minio-catalog directory not found at $DATALAKE_DIR"
    exit 1
fi

# Step 1: Start Data Lake (MinIO + Nessie)
echo "📦 Step 1: Starting Data Lake (MinIO + Nessie)..."
cd "$DATALAKE_DIR"

# Check if already running
if docker ps | grep -q "minio\|nessie"; then
    echo "   ⚠️  Data Lake containers already running. Stopping first..."
    docker-compose down 2>/dev/null || true
fi

# Start data lake services
docker-compose up -d minio nessie minio-setup

echo "   ⏳ Waiting for MinIO and Nessie to be ready..."
sleep 10

# Verify MinIO is accessible
if curl -sf http://localhost:19000/minio/health/live > /dev/null 2>&1; then
    echo "   ✅ MinIO is running on port 19000"
else
    echo "   ⚠️  MinIO may not be fully ready yet"
fi

# Verify Nessie is accessible
if curl -sf http://localhost:19120/api/v2/config > /dev/null 2>&1; then
    echo "   ✅ Nessie is running on port 19120"
else
    echo "   ⚠️  Nessie may not be fully ready yet"
fi

echo ""

# Step 2: Setup ClickHouse
echo "📦 Step 2: Setting up ClickHouse version 25.8..."
cd "$OSS_MAC_SETUP_DIR"
./set.sh 25.8

echo ""
echo "▶️  Starting ClickHouse 25.8..."
./start.sh

echo ""
echo "⏳ Waiting for ClickHouse to be ready..."
sleep 5

# Verify installation (uses default port 8123)
echo ""
echo "✅ Verifying ClickHouse 25.8 installation..."
VERSION_CHECK=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION_CHECK" ]; then
    echo "   ✅ $VERSION_CHECK"
else
    echo "   ⚠️  Could not verify version"
fi

echo ""
echo "📍 Connection Information:"
echo ""
echo "ClickHouse 25.8:"
echo "   🌐 Web UI: http://localhost:8123/play"
echo "   📡 HTTP API: http://localhost:8123"
echo "   🔌 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "MinIO (Data Lake Storage):"
echo "   🌐 Console: http://localhost:19001"
echo "   📡 API: http://localhost:19000"
echo "   👤 User: admin / Password: password123"
echo "   📦 Bucket: warehouse"
echo ""
echo "Nessie (Catalog):"
echo "   📡 API: http://localhost:19120"
echo ""
echo "🔧 Management Commands:"
echo "   cd $OSS_MAC_SETUP_DIR"
echo "   ./status.sh          - Check ClickHouse status"
echo "   ./client.sh 2508     - Connect to ClickHouse CLI"
echo "   ./stop.sh            - Stop ClickHouse"
echo ""
echo "   cd $DATALAKE_DIR"
echo "   docker-compose down  - Stop Data Lake services"
echo ""
echo "✅ ClickHouse 25.8 + Data Lake setup complete!"
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
