#!/bin/bash

echo "🔌 ClickHouse Client Connection"
echo "============================"

# Check container status
if ! docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "❌ ClickHouse is not running."
    echo "   To start: ./start.sh"
    exit 1
fi

# Check service status
if ! curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse service is not responding."
    echo "   Check status: ./status.sh"
    exit 1
fi

echo "✅ Connecting..."
echo "   To exit: type 'exit' or press Ctrl+D"
echo ""

# Connect to client
docker-compose exec clickhouse clickhouse-client
