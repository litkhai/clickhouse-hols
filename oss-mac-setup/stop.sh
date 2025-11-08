#!/bin/bash

echo "🛑 Stopping ClickHouse..."
echo "======================="

# Stop with Docker Compose
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Stopping with Docker Compose..."
    docker-compose down
else
    echo "▶️  Stopping container directly..."
    docker stop clickhouse-oss 2>/dev/null || true
    docker rm clickhouse-oss 2>/dev/null || true
fi

# Check status
if docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "⚠️  Container is still running."
    echo "   Force stop: docker kill clickhouse-oss"
else
    echo "✅ ClickHouse stopped successfully."
fi

echo ""
echo "🔧 To restart: ./start.sh"
