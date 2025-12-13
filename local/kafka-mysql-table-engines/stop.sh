#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Stopping Kafka-MySQL-ClickHouse Services"
echo "=========================================="

echo ""
echo "Stopping Docker containers..."
docker-compose down

echo ""
echo "✅ All services stopped"
echo ""
echo "To remove all data volumes, run:"
echo "  docker-compose down -v"
echo ""
