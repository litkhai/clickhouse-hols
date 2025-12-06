#!/bin/bash
echo "📜 ClickHouse Logs"
echo "=================="

if [ "$1" = "-f" ]; then
    echo "Following logs... (Press Ctrl+C to stop)"
    docker-compose logs -f clickhouse
else
    echo "Last 50 lines:"
    docker-compose logs --tail=50 clickhouse
    echo ""
    echo "Use './scripts/logs.sh -f' to follow logs in real-time"
fi
