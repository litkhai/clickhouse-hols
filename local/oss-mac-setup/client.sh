#!/bin/bash

echo "🔌 ClickHouse Client Connection"
echo "================================"

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

# Function to convert port to version
port_to_version() {
    local port=$1
    # Load configured versions
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            if [ "$(version_to_port "$version")" = "$port" ]; then
                echo "$version"
                return
            fi
        done
    fi
    echo ""
}

# Check if port parameter is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Port number required"
    echo ""
    echo "Usage: ./client.sh <PORT>"
    echo ""
    echo "Available versions and ports:"
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            PORT=$(version_to_port "$version")
            echo "   - Version ${version}: port ${PORT}"
        done
    fi
    exit 1
fi

PORT=$1
VERSION=$(port_to_version "$PORT")

if [ -z "$VERSION" ]; then
    echo "❌ Error: Port ${PORT} is not configured"
    echo ""
    echo "Available versions and ports:"
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            VPORT=$(version_to_port "$version")
            echo "   - Version ${version}: port ${VPORT}"
        done
    fi
    exit 1
fi

CONTAINER_NAME="clickhouse-${VERSION//./-}"

# Check container status
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ ClickHouse version ${VERSION} (port ${PORT}) is not running."
    echo "   To start: ./start.sh"
    exit 1
fi

# Check service status
if ! curl -s http://localhost:${PORT}/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse version ${VERSION} service is not responding."
    echo "   Check status: ./status.sh"
    exit 1
fi

echo "✅ Connecting to version ${VERSION} on port ${PORT}..."
echo "   To exit: type 'exit' or press Ctrl+D"
echo ""

# Connect to client
docker exec -it ${CONTAINER_NAME} clickhouse-client
