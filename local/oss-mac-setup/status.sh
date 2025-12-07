#!/bin/bash

echo "📊 ClickHouse Multi-Version Status"
echo "===================================="

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

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    echo "❌ .env file not found. Please run ./set.sh first."
    exit 1
fi

echo ""
echo "📦 Configured versions: ${VERSIONS[*]}"
echo ""

# Container status
echo "🐳 Container Status:"
ANY_RUNNING=false
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        STATUS=$(docker ps --format '{{.Status}}' --filter "name=^${CONTAINER_NAME}$")
        echo "   ✅ ${CONTAINER_NAME}: ${STATUS}"
        ANY_RUNNING=true
    else
        echo "   ❌ ${CONTAINER_NAME}: Not running"
    fi
done

if [ "$ANY_RUNNING" = false ]; then
    echo ""
    echo "❌ No ClickHouse containers are running."
    echo "   To start: ./start.sh"
    echo ""
    exit 1
fi

echo ""

# Service health check for each version
echo "💓 Service Status:"
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

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo ""
        echo "   Version ${version} (port ${HTTP_PORT}):"

        if curl -s http://localhost:${HTTP_PORT}/ping > /dev/null 2>&1; then
            echo "      ✅ HTTP Interface: OK (port ${HTTP_PORT})"

            # Version information
            VERSION_INFO=$(curl -s http://localhost:${HTTP_PORT}/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
            if [ -n "$VERSION_INFO" ]; then
                echo "      ✅ ${VERSION_INFO}"
            fi
        else
            echo "      ❌ HTTP Interface: Connection failed (port ${HTTP_PORT})"
        fi

        # TCP port check
        if nc -z localhost ${TCP_PORT} 2>/dev/null; then
            echo "      ✅ TCP Interface: OK (port ${TCP_PORT})"
        else
            echo "      ❌ TCP Interface: Connection failed (port ${TCP_PORT})"
        fi
    fi
done

echo ""

# Resource usage
echo "💾 Resource Usage:"
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" ${CONTAINER_NAME} 2>/dev/null
    fi
done

echo ""

# Volume information
echo "💿 Data Volumes:"
docker volume ls | grep clickhouse || echo "No volumes found."

echo ""
echo "🔧 Management Commands:"
echo "   ./start.sh          - Start all ClickHouse versions"
echo "   ./stop.sh           - Stop all versions"
echo "   ./client.sh <PORT>  - Connect to specific version"
echo "   docker-compose logs -f  - View real-time logs"
echo ""
echo "📍 Connection URLs:"
for version in "${VERSIONS[@]}"; do
    # Use default ports (8123, 9000) if only one version is configured
    if [ ${#VERSIONS[@]} -eq 1 ]; then
        HTTP_PORT="8123"
    else
        HTTP_PORT=$(version_to_port "$version")
    fi
    echo "   Version ${version}: http://localhost:${HTTP_PORT}/play"
done
