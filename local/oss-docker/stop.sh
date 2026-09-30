#!/bin/bash

echo "🛑 Stopping ClickHouse Multi-Version..."
echo "======================================="

# Check for cleanup flag
CLEANUP=false
if [ "$1" = "--cleanup" ] || [ "$1" = "-c" ]; then
    CLEANUP=true
    echo ""
    echo "⚠️  Cleanup mode enabled - will delete all data!"
    echo ""
fi

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    VERSIONS=()
fi

# Stop with Docker Compose
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Stopping with Docker Compose..."
    if [ "$CLEANUP" = true ]; then
        docker compose down -v
    else
        docker compose down
    fi
else
    echo "▶️  Stopping containers directly..."
    for version in "${VERSIONS[@]}"; do
        CONTAINER_NAME="clickhouse-${version//./-}"
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
    done
fi

# Check status
echo ""
echo "📊 Container status:"
STILL_RUNNING=false
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "   ⚠️  ${CONTAINER_NAME} is still running."
        STILL_RUNNING=true
    else
        echo "   ✓ ${CONTAINER_NAME} stopped"
    fi
done

if [ "$STILL_RUNNING" = true ]; then
    echo ""
    echo "⚠️  Some containers are still running."
    echo "   Force stop: docker compose kill"
else
    echo ""
    echo "✅ All ClickHouse containers stopped successfully."
fi

# Additional cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo ""
    echo "🗑️  Removing Docker volumes..."
    for version in "${VERSIONS[@]}"; do
        docker volume rm clickhouse-oss_clickhouse_data_${version//./_} 2>/dev/null && echo "   ✓ Removed data volume for ${version}" || true
        docker volume rm clickhouse-oss_clickhouse_logs_${version//./_} 2>/dev/null && echo "   ✓ Removed logs volume for ${version}" || true
    done

    echo ""
    echo "🧹 Cleaning up network..."
    docker network rm clickhouse-network 2>/dev/null && echo "   ✓ Removed clickhouse-network" || true

    echo ""
    echo "🗑️  Removing Docker images..."
    for version in "${VERSIONS[@]}"; do
        docker rmi clickhouse/clickhouse-server:${version} 2>/dev/null && echo "   ✓ Removed image ${version}" || true
    done

    echo ""
    echo "✅ Complete cleanup finished!"
fi

echo ""
if [ "$CLEANUP" = true ]; then
    echo "🔧 To setup again: ./set.sh <VERSION1> <VERSION2> ..."
else
    echo "🔧 To restart: ./start.sh"
    echo "🧹 To stop with cleanup: ./stop.sh --cleanup"
fi
