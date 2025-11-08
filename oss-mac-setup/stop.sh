#!/bin/bash

echo "🛑 Stopping ClickHouse..."
echo "======================="

# Check for cleanup flag
CLEANUP=false
if [ "$1" = "--cleanup" ] || [ "$1" = "-c" ]; then
    CLEANUP=true
    echo ""
    echo "⚠️  Cleanup mode enabled - will delete all data!"
    echo ""
fi

# Stop with Docker Compose
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Stopping with Docker Compose..."
    if [ "$CLEANUP" = true ]; then
        docker-compose down -v
    else
        docker-compose down
    fi
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

# Additional cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo ""
    echo "🗑️  Removing Docker volumes..."
    docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null && echo "   ✓ Removed clickhouse_data volume" || true
    docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null && echo "   ✓ Removed clickhouse_logs volume" || true

    echo ""
    echo "🧹 Cleaning up network..."
    docker network rm clickhouse-network 2>/dev/null && echo "   ✓ Removed clickhouse-network" || true

    echo ""
    echo "✅ Complete cleanup finished!"
fi

echo ""
if [ "$CLEANUP" = true ]; then
    echo "🔧 To setup again: cd /path/to/setup && ./set.sh"
else
    echo "🔧 To restart: ./start.sh"
    echo "🧹 To stop with cleanup: ./stop.sh --cleanup"
fi
