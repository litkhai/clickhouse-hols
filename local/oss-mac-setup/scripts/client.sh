#!/bin/bash
echo "🔌 Connecting to ClickHouse..."
echo "Type 'exit' or press Ctrl+D to disconnect"
echo ""

docker-compose exec clickhouse clickhouse-client -u admin --password clickhouse
