#!/bin/bash
echo "📊 ClickHouse Status"
echo "===================="

echo "🐳 Container Status:"
docker-compose ps

echo ""
echo "💓 Service Health:"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "✅ HTTP Interface: OK (port 8123)"
else
    echo "❌ HTTP Interface: Failed (port 8123)"
fi

echo ""
echo "📋 Version Info:"
VERSION=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
if [ -n "$VERSION" ]; then
    echo "✅ $VERSION"
else
    echo "❌ Could not retrieve version"
fi

echo ""
echo "💾 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" clickhouse-oss 2>/dev/null || echo "Container not running"
