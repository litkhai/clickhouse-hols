#!/bin/bash

echo "🚀 Starting ClickHouse..."
echo "========================"

# Clean up existing container if present
if docker ps -a --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "🔄 Cleaning up existing container..."
    docker stop clickhouse-oss 2>/dev/null || true
    docker rm clickhouse-oss 2>/dev/null || true
    docker-compose down 2>/dev/null || true
fi

# Pull latest image
echo "📥 Pulling ClickHouse image..."
docker-compose pull

# Start ClickHouse
echo "▶️  Starting ClickHouse container..."
docker-compose up -d

# Wait for initialization
echo "⏳ Waiting for ClickHouse initialization..."
echo "   (up to 45 seconds)"

# Check status (wait up to 45 seconds)
for i in {1..45}; do
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        echo ""
        echo "✅ ClickHouse started successfully!"
        break
    fi

    if [ $i -eq 45 ]; then
        echo ""
        echo "⚠️  Startup is taking longer than expected. Check logs:"
        echo "   docker-compose logs clickhouse"
        exit 1
    fi

    echo -ne "\r   Waiting... ${i}s"
    sleep 1
done

echo ""
echo "🎯 Connection Information:"
echo "   📍 Web UI: http://localhost:8123/play"
echo "   📍 HTTP API: http://localhost:8123"
echo "   📍 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   ./stop.sh              - Stop ClickHouse (preserve data)"
echo "   ./stop.sh --cleanup    - Stop and delete all data"
echo "   ./status.sh            - Check status and resource usage"
echo "   ./client.sh            - Connect to CLI client"
echo "   docker logs clickhouse-oss - View container logs"
echo ""
echo "✅ ClickHouse is ready!"
