#!/bin/bash

echo "🧹 ClickHouse Complete Cleanup"
echo "======================"
echo ""
echo "⚠️  Warning: This will delete all ClickHouse data!"
echo "   - All databases"
echo "   - All tables"
echo "   - All logs"
echo ""

read -p "Are you sure you want to delete all data? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

echo "🛑 Stopping and removing containers..."
docker-compose down -v

echo "🗑️  Removing Docker volumes..."
docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null || true
docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null || true

echo "🧹 Cleaning up network..."
docker network rm clickhouse-network 2>/dev/null || true

echo "✅ Cleanup complete!"
echo ""
echo "🔄 To restart: ./start.sh"
