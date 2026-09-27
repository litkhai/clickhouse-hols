#!/bin/bash

echo "🚀 Starting ClickHouse Multi-Version..."
echo "======================================"

# Function to convert version to port number
version_to_port() {
    local version=$1
    if [ "$version" = "latest" ]; then
        echo "9999"
    else
        # Split version by dot and pad the minor version to 2 digits
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        printf "%02d%02d" "$major" "$minor"
    fi
}

# Load configured versions from .env
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    echo "❌ .env file not found. Please run ./set.sh first."
    exit 1
fi

echo "📦 Configured versions: ${VERSIONS[*]}"
echo ""

# Clean up existing containers if present
echo "🔄 Cleaning up old containers..."
docker-compose down 2>/dev/null || true

# Pull latest images
echo "📥 Pulling ClickHouse images..."
docker-compose pull

# Start all ClickHouse containers
echo "▶️  Starting ClickHouse containers..."
docker-compose up -d

echo ""
echo "⏳ Waiting for ClickHouse initialization..."
echo "   (checking each version, up to 45 seconds per version)"
echo ""

# Check status for each version
ALL_STARTED=true
for version in "${VERSIONS[@]}"; do
    # Use default ports (8123, 9000) if only one version is configured
    if [ ${#VERSIONS[@]} -eq 1 ]; then
        HTTP_PORT="8123"
        TCP_PORT="9000"
    else
        PORT=$(version_to_port "$version")
        HTTP_PORT="${PORT}"
        TCP_PORT="${PORT}1"
    fi
    CONTAINER_NAME="clickhouse-${version//./-}"

    echo "Checking version ${version} on port ${HTTP_PORT}..."

    # Wait up to 45 seconds
    STARTED=false
    for i in {1..45}; do
        if curl -s http://localhost:${HTTP_PORT}/ping > /dev/null 2>&1; then
            echo "✅ Version ${version} started successfully! (port ${HTTP_PORT})"
            STARTED=true
            break
        fi

        echo -ne "\r   Waiting... ${i}s"
        sleep 1
    done

    if [ "$STARTED" = false ]; then
        echo ""
        echo "⚠️  Version ${version} startup timeout. Check logs:"
        echo "   docker logs ${CONTAINER_NAME}"
        ALL_STARTED=false
    fi
    echo ""
done

if [ "$ALL_STARTED" = true ]; then
    echo "✅ All ClickHouse versions started successfully!"
else
    echo "⚠️  Some versions failed to start. Check logs above."
fi

echo ""
echo "🎯 Connection Information:"
for version in "${VERSIONS[@]}"; do
    # Use default ports (8123, 9000) if only one version is configured
    if [ ${#VERSIONS[@]} -eq 1 ]; then
        HTTP_PORT="8123"
        TCP_PORT="9000"
    else
        PORT=$(version_to_port "$version")
        HTTP_PORT="${PORT}"
        TCP_PORT="${PORT}1"
    fi
    echo "   Version ${version}:"
    echo "      📍 Web UI: http://localhost:${HTTP_PORT}/play"
    echo "      📍 HTTP API: http://localhost:${HTTP_PORT}"
    echo "      📍 TCP: localhost:${TCP_PORT}"
    echo "      👤 User: default (no password)"
    echo ""
done

echo "🔧 Management Commands:"
echo "   ./stop.sh              - Stop all versions (preserve data)"
echo "   ./stop.sh --cleanup    - Stop and delete all data"
echo "   ./status.sh            - Check status and resource usage"
if [ ${#VERSIONS[@]} -eq 1 ]; then
    echo "   ./client.sh ${HTTP_PORT}     - Connect to ClickHouse client"
else
    echo "   ./client.sh <PORT>     - Connect to specific version"
    echo "   Example: ./client.sh ${HTTP_PORT} (for version ${version})"
fi
echo ""
echo "✅ ClickHouse is ready! (No get_mempolicy errors with seccomp profile)"
