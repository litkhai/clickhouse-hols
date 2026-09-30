#!/bin/bash

echo "🧹 ClickHouse Multi-Version Complete Cleanup"
echo "============================================="
echo ""
echo "⚠️  Warning: This will delete all ClickHouse data!"
echo "   - All databases from all versions"
echo "   - All tables from all versions"
echo "   - All logs"
echo ""

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
    echo "Configured versions: ${VERSIONS[*]}"
    echo ""
else
    VERSIONS=()
fi

read -p "Are you sure you want to delete all data? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

echo "🛑 Stopping and removing containers..."
docker compose down -v

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
echo "✅ Cleanup complete!"
echo ""
echo "🔄 To setup again: ./set.sh <VERSION1> <VERSION2> ..."
