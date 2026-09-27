#!/bin/bash
echo "🚀 Starting ClickHouse..."
docker-compose up -d

echo "⏳ Waiting for ClickHouse to be ready..."
sleep 10

echo "🔍 Checking health..."
docker-compose ps

echo "✅ ClickHouse is running!"
echo "📍 HTTP Interface: http://localhost:8123"
echo "📍 Web UI: http://localhost:8123/play"
echo "📍 TCP Interface: localhost:9000"
echo "👤 Username: admin"
echo "🔐 Password: clickhouse"
