#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Kafka-MySQL-ClickHouse Environment Setup"
echo "=========================================="

# Create directories
echo ""
echo "[1/4] Creating necessary directories..."
mkdir -p mysql-init
mkdir -p clickhouse-init
mkdir -p scripts
mkdir -p logs

# Create MySQL init script
echo ""
echo "[2/4] Creating MySQL initialization script..."
cat > mysql-init/01-init.sql <<'EOF'
-- Create target table for ClickHouse MySQL engine
CREATE TABLE IF NOT EXISTS testdb.aggregated_events (
    event_date DATE NOT NULL,
    query_kind VARCHAR(50) NOT NULL,
    query_count BIGINT NOT NULL,
    total_duration_ms BIGINT NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (event_date, query_kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create raw events table for monitoring
CREATE TABLE IF NOT EXISTS testdb.raw_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_time TIMESTAMP NOT NULL,
    query_kind VARCHAR(50) NOT NULL,
    query_duration_ms INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

GRANT ALL PRIVILEGES ON testdb.* TO 'clickhouse'@'%';
FLUSH PRIVILEGES;
EOF

# Create ClickHouse init script
echo ""
echo "[3/4] Creating ClickHouse initialization script..."
cat > clickhouse-init/01-init.sql <<'EOF'
-- Create Kafka source table
CREATE TABLE IF NOT EXISTS default.kafka_events (
    event_time DateTime DEFAULT now(),
    query_kind String,
    query_duration_ms UInt32
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'test-events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

-- Create buffer table for Kafka data
CREATE TABLE IF NOT EXISTS default.events_buffer (
    event_time DateTime,
    query_kind String,
    query_duration_ms UInt32
) ENGINE = MergeTree()
ORDER BY (event_time, query_kind);

-- Create MySQL table engine
CREATE TABLE IF NOT EXISTS default.mysql_aggregated_events (
    event_date Date,
    query_kind String,
    query_count UInt64,
    total_duration_ms UInt64
) ENGINE = MySQL('mysql:3306', 'testdb', 'aggregated_events', 'clickhouse', 'clickhouse');

-- Create materialized view: Kafka -> Buffer
CREATE MATERIALIZED VIEW IF NOT EXISTS default.kafka_to_buffer_mv
TO default.events_buffer
AS
SELECT
    event_time,
    query_kind,
    query_duration_ms
FROM default.kafka_events;

-- Create materialized view with block size settings: Buffer -> MySQL
CREATE MATERIALIZED VIEW IF NOT EXISTS default.buffer_to_mysql_mv
TO default.mysql_aggregated_events
AS
SELECT
    toDate(event_time) AS event_date,
    query_kind,
    count() AS query_count,
    sum(query_duration_ms) AS total_duration_ms
FROM default.events_buffer
GROUP BY event_date, query_kind
SETTINGS
    max_block_size = 1000,
    min_insert_block_size_rows = 5000,
    min_insert_block_size_bytes = 268435456;
EOF

# Create Python Kafka producer
echo ""
echo "[4/4] Creating Kafka producer script..."
cat > scripts/kafka_producer.py <<'EOF'
#!/usr/bin/env python3

import json
import time
import random
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import NoBrokersAvailable
import sys

def wait_for_kafka(bootstrap_servers, max_retries=30, retry_interval=2):
    """Wait for Kafka to be available"""
    for i in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            producer.close()
            print(f"✅ Kafka is ready at {bootstrap_servers}")
            return True
        except NoBrokersAvailable:
            print(f"⏳ Waiting for Kafka... ({i+1}/{max_retries})")
            time.sleep(retry_interval)
    return False

def produce_events(bootstrap_servers, topic, num_events, batch_size=100):
    """Produce test events to Kafka"""

    if not wait_for_kafka(bootstrap_servers):
        print("❌ Failed to connect to Kafka")
        sys.exit(1)

    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks='all',
        retries=3
    )

    query_kinds = ['SELECT', 'INSERT', 'ALTER', 'CREATE', 'UPDATE', 'DELETE']

    print(f"\n📤 Starting to produce {num_events} events...")
    print(f"Topic: {topic}")
    print(f"Batch size: {batch_size}\n")

    start_time = time.time()

    try:
        for i in range(num_events):
            event = {
                'event_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'query_kind': random.choice(query_kinds),
                'query_duration_ms': random.randint(10, 5000)
            }

            future = producer.send(topic, event)

            if (i + 1) % batch_size == 0:
                producer.flush()
                elapsed = time.time() - start_time
                rate = (i + 1) / elapsed
                print(f"✅ Sent {i+1}/{num_events} events ({rate:.1f} events/sec)")

        producer.flush()

    except KeyboardInterrupt:
        print("\n⚠️  Interrupted by user")
    except Exception as e:
        print(f"\n❌ Error: {e}")
    finally:
        producer.close()

    elapsed = time.time() - start_time
    final_rate = num_events / elapsed
    print(f"\n✅ Completed!")
    print(f"Total events: {num_events}")
    print(f"Total time: {elapsed:.2f} seconds")
    print(f"Average rate: {final_rate:.1f} events/sec")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Kafka Event Producer')
    parser.add_argument('--bootstrap-servers', default='localhost:9092',
                        help='Kafka bootstrap servers')
    parser.add_argument('--topic', default='test-events',
                        help='Kafka topic name')
    parser.add_argument('--num-events', type=int, default=10000,
                        help='Number of events to produce')
    parser.add_argument('--batch-size', type=int, default=100,
                        help='Flush after this many events')

    args = parser.parse_args()

    produce_events(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic,
        num_events=args.num_events,
        batch_size=args.batch_size
    )
EOF

chmod +x scripts/kafka_producer.py

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Run './start.sh' to start all services"
echo "  2. Run './test-block-size.sh' to validate block size settings"
echo "  3. Run './stop.sh' to stop all services"
