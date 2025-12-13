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
