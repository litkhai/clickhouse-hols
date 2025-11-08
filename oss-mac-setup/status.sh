#!/bin/bash

echo "📊 ClickHouse Status"
echo "=================="

# Container status
echo "🐳 Container Status:"
if docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep clickhouse-oss; then
    echo ""
else
    echo "❌ ClickHouse container is not running."
    echo "   To start: ./start.sh"
    echo ""
    exit 1
fi

# Service health check
echo "💓 Service Status:"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "✅ HTTP Interface: OK (port 8123)"

    # Version information
    VERSION=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
    if [ -n "$VERSION" ]; then
        echo "✅ $VERSION"
    fi
else
    echo "❌ HTTP Interface: Connection failed (port 8123)"
fi

# TCP port check
if nc -z localhost 9000 2>/dev/null; then
    echo "✅ TCP Interface: OK (port 9000)"
else
    echo "❌ TCP Interface: Connection failed (port 9000)"
fi

echo ""

# Resource usage
echo "💾 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" clickhouse-oss 2>/dev/null

echo ""

# Volume information
echo "💿 Data Volumes:"
docker volume ls | grep clickhouse || echo "Volume information not found."

echo ""
echo "🔧 Management Commands:"
echo "   ./start.sh     - Start ClickHouse"
echo "   ./stop.sh      - Stop ClickHouse"
echo "   ./client.sh    - Connect to CLI client"
echo "   docker-compose logs -f  - View real-time logs"
