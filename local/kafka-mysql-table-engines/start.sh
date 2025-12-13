#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Starting Kafka-MySQL-ClickHouse Services"
echo "=========================================="

# Check if docker-compose exists
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose not found. Please install docker-compose first."
    exit 1
fi

# Start services
echo ""
echo "[1/5] Starting Docker containers..."
docker-compose up -d

# Wait for MySQL
echo ""
echo "[2/5] Waiting for MySQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec mysql mysqladmin ping -h localhost -u root -pclickhouse --silent &> /dev/null; then
        echo "✅ MySQL is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "⏳ Waiting for MySQL... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ MySQL failed to start"
    exit 1
fi

# Wait for Kafka
echo ""
echo "[3/5] Waiting for Kafka to be ready..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec kafka kafka-topics --bootstrap-server localhost:29092 --list &> /dev/null; then
        echo "✅ Kafka is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "⏳ Waiting for Kafka... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ Kafka failed to start"
    exit 1
fi

# Create Kafka topic
echo ""
echo "[4/5] Creating Kafka topic..."
docker exec kafka kafka-topics --create --if-not-exists \
    --bootstrap-server localhost:29092 \
    --topic test-events \
    --partitions 3 \
    --replication-factor 1 || true
echo "✅ Kafka topic created"

# Wait for ClickHouse
echo ""
echo "[5/5] Waiting for ClickHouse to be ready..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec clickhouse clickhouse-client --query "SELECT 1" &> /dev/null; then
        echo "✅ ClickHouse is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "⏳ Waiting for ClickHouse... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ ClickHouse failed to start"
    exit 1
fi

# Show status
echo ""
echo "=========================================="
echo "✅ All services are running!"
echo "=========================================="
echo ""
echo "Service Endpoints:"
echo "  - ClickHouse HTTP: http://localhost:8123"
echo "  - ClickHouse Native: localhost:9000"
echo "  - MySQL: localhost:3306"
echo "  - Kafka: localhost:9092"
echo "  - Zookeeper: localhost:2181"
echo ""
echo "Database Credentials:"
echo "  - MySQL:"
echo "    • User: clickhouse"
echo "    • Password: clickhouse"
echo "    • Database: testdb"
echo "  - ClickHouse:"
echo "    • User: default"
echo "    • Password: (empty)"
echo ""
echo "Next steps:"
echo "  1. Run './test-block-size.sh' to validate block size settings"
echo "  2. View logs: docker-compose logs -f [service-name]"
echo "  3. Stop services: ./stop.sh"
echo ""
