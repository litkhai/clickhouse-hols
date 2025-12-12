#!/usr/bin/env python3
"""
Quick ingestion test without scaling - just ingest and benchmark
"""

import os
import sys
import time
import json
from datetime import datetime
from pathlib import Path
import clickhouse_connect

# Load .env
def load_env():
    env_file = Path('.env')
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

load_env()

host = os.getenv('CLICKHOUSE_HOST')
port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
user = os.getenv('CLICKHOUSE_USER', 'default')
password = os.getenv('CLICKHOUSE_PASSWORD')
database = 'device360'
bucket = os.getenv('S3_BUCKET_NAME')
region = os.getenv('AWS_REGION', 'ap-northeast-2')

print("="*80)
print("Device360 Ingestion & Benchmark Test")
print("="*80)
print(f"Host: {host}")
print(f"Database: {database}")
print(f"S3: s3://{bucket}/device360/")
print("="*80)

client = clickhouse_connect.get_client(
    host=host,
    port=port,
    user=user,
    password=password,
    secure=True
)

print("\n✓ Connected")

# Drop and recreate
print("\nCreating fresh schema...")
client.command(f"DROP DATABASE IF EXISTS {database}")
time.sleep(2)
client.command(f"CREATE DATABASE IF NOT EXISTS {database}")

create_table = f"""
CREATE TABLE IF NOT EXISTS {database}.ad_requests
(
    event_ts DateTime,
    event_date Date,
    event_hour UInt8,
    device_id String,
    device_ip String,
    device_brand LowCardinality(String),
    device_model LowCardinality(String),
    os_version UInt16,
    platform_type UInt8,
    geo_country LowCardinality(String),
    geo_region LowCardinality(String),
    geo_city LowCardinality(String),
    geo_continent LowCardinality(String),
    geo_longitude Float32,
    geo_latitude Float32,
    app_id String,
    app_bundle String,
    app_name LowCardinality(String),
    app_category LowCardinality(String),
    ad_type UInt8,
    bid_floor Float32,
    final_cpm Float32,
    response_latency_ms UInt16,
    response_size_bytes UInt32,
    fraud_score_ifa UInt8,
    fraud_score_ip UInt8,
    network_type UInt8,
    screen_density UInt16,
    tracking_consent LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (device_id, event_date, event_ts)
"""

client.command(create_table)
print("✓ Table created (device_id-first ORDER BY)")

# Ingest
print("\nIngesting from S3...")
insert_query = f"""
INSERT INTO {database}.ad_requests
SELECT
    toDateTime(event_ts) as event_ts,
    toDate(event_date) as event_date,
    event_hour,
    device_id,
    device_ip,
    device_brand,
    device_model,
    os_version,
    platform_type,
    geo_country,
    geo_region,
    geo_city,
    geo_continent,
    geo_longitude,
    geo_latitude,
    app_id,
    app_bundle,
    app_name,
    app_category,
    ad_type,
    bid_floor,
    final_cpm,
    response_latency_ms,
    response_size_bytes,
    fraud_score_ifa,
    fraud_score_ip,
    network_type,
    screen_density,
    tracking_consent
FROM s3('https://{bucket}.s3.{region}.amazonaws.com/device360/device360_heavy_0001.json.gz',
         'JSONEachRow')
"""

start = time.time()
client.command(insert_query)
ingest_time = time.time() - start

row_count = client.command(f"SELECT count() FROM {database}.ad_requests")
rows_per_sec = row_count / ingest_time

print(f"✓ Ingestion complete!")
print(f"  Rows: {row_count:,}")
print(f"  Time: {ingest_time:.1f}s")
print(f"  Rate: {rows_per_sec:,.0f} rows/s")

# Run benchmarks
print("\n" + "="*80)
print("Running Benchmarks")
print("="*80)

# Get sample device
sample_query = f"SELECT device_id, count() as cnt FROM {database}.ad_requests GROUP BY device_id ORDER BY cnt DESC LIMIT 1"
result = client.query(sample_query)
sample_device_id = result.result_rows[0][0]
sample_count = result.result_rows[0][1]
print(f"\nSample device: {sample_device_id} ({sample_count:,} events)")

queries = [
    ("Single Device Lookup", f"SELECT * FROM {database}.ad_requests WHERE device_id = '{sample_device_id}' ORDER BY event_ts DESC LIMIT 1000"),
    ("Device Journey Timeline", f"SELECT event_ts, app_name, geo_country, final_cpm FROM {database}.ad_requests WHERE device_id = '{sample_device_id}' ORDER BY event_ts"),
    ("Device Count", f"SELECT count() as total, uniq(device_id) as devices FROM {database}.ad_requests"),
    ("Top 100 Devices", f"SELECT device_id, count() as cnt FROM {database}.ad_requests GROUP BY device_id ORDER BY cnt DESC LIMIT 100"),
    ("Geographic Distribution", f"SELECT geo_country, count() as cnt, uniq(device_id) as devices FROM {database}.ad_requests GROUP BY geo_country ORDER BY cnt DESC"),
    ("App Performance", f"SELECT app_name, count() as requests, uniq(device_id) as devices, avg(final_cpm) as avg_cpm FROM {database}.ad_requests GROUP BY app_name ORDER BY requests DESC LIMIT 50"),
    ("Bot Candidates", f"SELECT device_id, count() as cnt, uniq(device_ip) as ips FROM {database}.ad_requests GROUP BY device_id HAVING cnt > 50 ORDER BY cnt DESC LIMIT 100"),
    ("Hourly Pattern", f"SELECT event_hour, count() as requests FROM {database}.ad_requests GROUP BY event_hour ORDER BY event_hour"),
    ("Device Brand", f"SELECT device_brand, count() as requests FROM {database}.ad_requests GROUP BY device_brand ORDER BY requests DESC LIMIT 20"),
    ("Fraud Analysis", f"SELECT multiIf(fraud_score_ifa < 30, 'Low', fraud_score_ifa < 60, 'Medium', 'High') as risk, count() as cnt FROM {database}.ad_requests GROUP BY risk"),
]

results = []
for idx, (name, query) in enumerate(queries, 1):
    print(f"\n[{idx}/{len(queries)}] {name}")
    try:
        start = time.time()
        result = client.query(query)
        duration_ms = (time.time() - start) * 1000

        print(f"  ✓ {duration_ms:.1f}ms ({len(result.result_rows)} rows)")

        results.append({
            'name': name,
            'duration_ms': duration_ms,
            'rows': len(result.result_rows),
            'success': True
        })
    except Exception as e:
        print(f"  ✗ Error: {str(e)[:60]}")
        results.append({
            'name': name,
            'duration_ms': 0,
            'rows': 0,
            'success': False,
            'error': str(e)
        })

# Summary
successful = [r for r in results if r['success']]
durations = [r['duration_ms'] for r in successful]

print("\n" + "="*80)
print("SUMMARY")
print("="*80)

print(f"\nIngestion:")
print(f"  Rows: {row_count:,}")
print(f"  Duration: {ingest_time:.1f}s")
print(f"  Rate: {rows_per_sec:,.0f} rows/s")

print(f"\nQueries:")
print(f"  Total: {len(results)}")
print(f"  Successful: {len(successful)}")
if durations:
    print(f"  Average: {sum(durations)/len(durations):.1f}ms")
    print(f"  Median: {sorted(durations)[len(durations)//2]:.1f}ms")
    print(f"  Min: {min(durations):.1f}ms")
    print(f"  Max: {max(durations):.1f}ms")
    print(f"  < 100ms: {sum(1 for d in durations if d < 100)}/{len(durations)}")
    print(f"  < 500ms: {sum(1 for d in durations if d < 500)}/{len(durations)}")
    print(f"  < 1s: {sum(1 for d in durations if d < 1000)}/{len(durations)}")

print("="*80)

# Save
output = {
    'timestamp': datetime.now().isoformat(),
    'host': host,
    'database': database,
    'ingestion': {
        'rows': row_count,
        'duration_sec': ingest_time,
        'rows_per_sec': rows_per_sec
    },
    'queries': results
}

Path('results').mkdir(exist_ok=True)
result_file = Path('results') / f'quick_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'

with open(result_file, 'w') as f:
    json.dump(output, indent=2, fp=f)

print(f"\n✓ Results saved: {result_file}")
