#!/usr/bin/env python3
"""
Sequential Scale Test: 8 vCPU → 16 vCPU → 24 vCPU
Each test: drop DB, create schema, ingest data, measure time
Final test (24 vCPU): also run query benchmarks
"""

import os
import sys
import time
import json
from datetime import datetime
from pathlib import Path
import clickhouse_connect
import requests
from requests.auth import HTTPBasicAuth

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

# Configuration
host = os.getenv('CLICKHOUSE_HOST')
port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
user = os.getenv('CLICKHOUSE_USER', 'default')
password = os.getenv('CLICKHOUSE_PASSWORD')
database = 'device360'  # 명시적으로 device360 사용

chc_key_id = os.getenv('CHC_KEY_ID')
chc_key_secret = os.getenv('CHC_KEY_SECRET')
chc_org_id = os.getenv('CHC_ORG_ID')
chc_service_id = os.getenv('CHC_SERVICE_ID')

bucket = os.getenv('S3_BUCKET_NAME')
region = os.getenv('AWS_REGION')

print("="*80)
print("Device360 Sequential Scale Test")
print("="*80)
print(f"Host: {host}")
print(f"Database: {database}")
print(f"S3 Bucket: s3://{bucket}/device360/")
print(f"Test sequence: 8 vCPU → 16 vCPU → 24 vCPU")
print("="*80)

# Connect to ClickHouse
client = clickhouse_connect.get_client(
    host=host,
    port=port,
    user=user,
    password=password,
    secure=True
)
print("\n✓ Connected to ClickHouse")

def scale_service(target_memory_gb):
    """Scale service to target total memory"""
    print(f"\nScaling service to {target_memory_gb}GB total memory...")

    url = f"https://api.clickhouse.cloud/v1/organizations/{chc_org_id}/services/{chc_service_id}"

    payload = {
        "minTotalMemoryGb": target_memory_gb,
        "maxTotalMemoryGb": target_memory_gb
    }

    try:
        response = requests.patch(
            url,
            auth=HTTPBasicAuth(chc_key_id, chc_key_secret),
            headers={'Content-Type': 'application/json'},
            json=payload
        )

        if response.status_code in [200, 202]:
            print(f"✓ Scaling initiated to {target_memory_gb}GB")
            print("  Waiting 90 seconds for scaling to complete...")
            time.sleep(90)
            return True
        else:
            print(f"✗ Scaling failed: {response.status_code}")
            print(response.text)
            return False

    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def create_schema():
    """Create device360 database and ad_requests table"""
    print("\nCreating schema...")

    # Drop database
    client.command(f"DROP DATABASE IF EXISTS {database}")
    time.sleep(3)

    # Create database
    client.command(f"CREATE DATABASE IF NOT EXISTS {database}")

    # Create table with device_id-first ORDER BY
    create_table_sql = f"""
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
    SETTINGS index_granularity = 8192
    """

    client.command(create_table_sql)
    print("✓ Schema created (device_id-first ORDER BY)")

def ingest_data():
    """Ingest data from S3 using IAM role"""
    print("\nIngesting data from S3...")

    # Use s3 URL format that works with IAM role
    insert_query = f"""
    INSERT INTO {database}.ad_requests
    SELECT
        parseDateTime(event_ts, '%Y-%m-%d %H:%i:%s') as event_ts,
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
    FROM s3('s3://{bucket}/device360/*.json.gz',
             '{os.getenv("AWS_ACCESS_KEY_ID")}',
             '{os.getenv("AWS_SECRET_ACCESS_KEY")}',
             'JSONEachRow')
    SETTINGS input_format_import_nested_json = 1
    """

    start_time = time.time()
    try:
        client.command(insert_query)
        ingest_time = time.time() - start_time

        # Get row count
        row_count = client.command(f"SELECT count() FROM {database}.ad_requests")
        rows_per_sec = row_count / ingest_time if ingest_time > 0 else 0

        print(f"✓ Ingestion complete!")
        print(f"  Rows: {row_count:,}")
        print(f"  Time: {ingest_time:.1f}s ({ingest_time/60:.1f} min)")
        print(f"  Rate: {rows_per_sec:,.0f} rows/s")

        return {
            'rows': row_count,
            'duration_sec': ingest_time,
            'rows_per_sec': rows_per_sec,
            'success': True
        }

    except Exception as e:
        print(f"✗ Ingestion failed: {e}")
        return {
            'rows': 0,
            'duration_sec': 0,
            'rows_per_sec': 0,
            'success': False,
            'error': str(e)
        }

def run_benchmarks():
    """Run query benchmarks (only for 24 vCPU test)"""
    print("\n" + "="*80)
    print("Running Query Benchmarks")
    print("="*80)

    # Get sample device
    sample_query = f"""
    SELECT device_id, count() as cnt
    FROM {database}.ad_requests
    GROUP BY device_id
    ORDER BY cnt DESC
    LIMIT 1
    """
    result = client.query(sample_query)
    if not result.result_rows:
        print("✗ No data found")
        return []

    sample_device_id = result.result_rows[0][0]
    sample_count = result.result_rows[0][1]
    print(f"\nSample device: {sample_device_id} ({sample_count:,} events)")

    # Test queries
    test_queries = [
        ("Single Device Lookup", f"SELECT * FROM {database}.ad_requests WHERE device_id = '{sample_device_id}' ORDER BY event_ts DESC LIMIT 1000"),
        ("Device Journey Timeline", f"SELECT event_ts, app_name, geo_country, geo_city, final_cpm FROM {database}.ad_requests WHERE device_id = '{sample_device_id}' ORDER BY event_ts"),
        ("Device Count", f"SELECT count() as total_requests, uniq(device_id) as unique_devices FROM {database}.ad_requests"),
        ("Top 100 Devices", f"SELECT device_id, count() as cnt FROM {database}.ad_requests GROUP BY device_id ORDER BY cnt DESC LIMIT 100"),
        ("Geographic Distribution", f"SELECT geo_country, count() as cnt, uniq(device_id) as devices FROM {database}.ad_requests GROUP BY geo_country ORDER BY cnt DESC"),
        ("App Performance", f"SELECT app_name, count() as requests, uniq(device_id) as unique_devices, avg(final_cpm) as avg_cpm FROM {database}.ad_requests GROUP BY app_name ORDER BY requests DESC LIMIT 50"),
        ("High-Frequency Devices (Bot Candidates)", f"SELECT device_id, count() as cnt, uniq(device_ip) as ips, uniq(geo_country) as countries FROM {database}.ad_requests GROUP BY device_id HAVING cnt > 50 ORDER BY cnt DESC LIMIT 100"),
        ("Hourly Pattern", f"SELECT event_hour, count() as requests, uniq(device_id) as devices FROM {database}.ad_requests GROUP BY event_hour ORDER BY event_hour"),
        ("Device Brand Distribution", f"SELECT device_brand, count() as requests, uniq(device_id) as devices FROM {database}.ad_requests GROUP BY device_brand ORDER BY requests DESC LIMIT 20"),
        ("Fraud Score Analysis", f"SELECT multiIf(fraud_score_ifa < 30, 'Low', fraud_score_ifa < 60, 'Medium', 'High') as risk_level, count() as cnt, uniq(device_id) as devices FROM {database}.ad_requests GROUP BY risk_level"),
    ]

    results = []
    for idx, (query_name, query_sql) in enumerate(test_queries, 1):
        print(f"\n[{idx}/{len(test_queries)}] {query_name}")
        try:
            start = time.time()
            result = client.query(query_sql)
            duration_ms = (time.time() - start) * 1000

            print(f"  ✓ {duration_ms:.1f}ms ({len(result.result_rows)} rows)")

            results.append({
                'name': query_name,
                'duration_ms': duration_ms,
                'rows': len(result.result_rows),
                'success': True
            })
        except Exception as e:
            print(f"  ✗ Error: {str(e)[:80]}")
            results.append({
                'name': query_name,
                'duration_ms': 0,
                'rows': 0,
                'success': False,
                'error': str(e)
            })

    # Print summary
    successful = [r for r in results if r['success']]
    if successful:
        durations = [r['duration_ms'] for r in successful]
        print(f"\nBenchmark Summary:")
        print(f"  Successful: {len(successful)}/{len(results)}")
        print(f"  Average: {sum(durations)/len(durations):.1f}ms")
        print(f"  Median: {sorted(durations)[len(durations)//2]:.1f}ms")
        print(f"  Min: {min(durations):.1f}ms")
        print(f"  Max: {max(durations):.1f}ms")
        print(f"  < 100ms: {sum(1 for d in durations if d < 100)}/{len(durations)}")
        print(f"  < 500ms: {sum(1 for d in durations if d < 500)}/{len(durations)}")
        print(f"  < 1s: {sum(1 for d in durations if d < 1000)}/{len(durations)}")

    return results

# Main test sequence
all_results = []

# Test configurations: (vcpu_label, total_memory_gb)
test_configs = [
    ("8 vCPU", 24),   # 8GB × 3 replicas
    ("16 vCPU", 48),  # 16GB × 3 replicas
    ("24 vCPU", 72),  # 24GB × 3 replicas
]

for idx, (vcpu_label, memory_gb) in enumerate(test_configs, 1):
    print("\n\n" + "#"*80)
    print(f"# TEST {idx}/3: {vcpu_label} Configuration ({memory_gb}GB total)")
    print("#"*80)

    test_start = time.time()

    # Scale service (skip for first test if already at 24GB)
    if idx == 1:
        # Check current size
        print("\nUsing current configuration (checking if scaling needed)...")
        url = f"https://api.clickhouse.cloud/v1/organizations/{chc_org_id}/services/{chc_service_id}"
        response = requests.get(url, auth=HTTPBasicAuth(chc_key_id, chc_key_secret))
        if response.status_code == 200:
            current = response.json()['result']['minTotalMemoryGb']
            print(f"  Current: {current}GB")
            if current != memory_gb:
                if not scale_service(memory_gb):
                    print(f"✗ Scaling failed, skipping this test")
                    continue
    else:
        if not scale_service(memory_gb):
            print(f"✗ Scaling failed, skipping this test")
            continue

    # Create schema
    create_schema()

    # Ingest data
    ingest_result = ingest_data()

    # Run benchmarks (only for 24 vCPU)
    if vcpu_label == "24 vCPU" and ingest_result['success']:
        benchmark_results = run_benchmarks()
    else:
        benchmark_results = None

    test_duration = time.time() - test_start

    # Store results
    test_result = {
        'config': vcpu_label,
        'memory_gb': memory_gb,
        'test_duration_sec': test_duration,
        'ingestion': ingest_result,
        'benchmarks': benchmark_results,
        'timestamp': datetime.now().isoformat()
    }

    all_results.append(test_result)

# Save results
Path('results').mkdir(exist_ok=True)
result_file = Path('results') / f'scale_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'

with open(result_file, 'w') as f:
    json.dump({
        'test_date': datetime.now().isoformat(),
        'host': host,
        'database': database,
        'results': all_results
    }, f, indent=2)

# Print final summary
print("\n\n" + "="*80)
print("FINAL SUMMARY")
print("="*80)

print("\nIngestion Performance:")
print("-"*80)
print(f"{'Config':<15} {'Rows':>15} {'Duration':>12} {'Rows/sec':>15} {'Improvement'}")
print("-"*80)

baseline_rate = None
for result in all_results:
    if result['ingestion']['success']:
        ing = result['ingestion']
        rate = ing['rows_per_sec']

        if baseline_rate is None:
            baseline_rate = rate
            improvement = "Baseline"
        else:
            improvement = f"{rate / baseline_rate:.2f}x"

        print(f"{result['config']:<15} {ing['rows']:>15,} {ing['duration_sec']:>12.1f}s {rate:>15,.0f} {improvement}")

print("-"*80)

# Query performance summary (24 vCPU)
bench_result = next((r['benchmarks'] for r in all_results if r['benchmarks']), None)
if bench_result:
    successful = [b for b in bench_result if b['success']]
    if successful:
        durations = [b['duration_ms'] for b in successful]
        print(f"\nQuery Performance (24 vCPU):")
        print(f"  Total queries: {len(bench_result)}")
        print(f"  Successful: {len(successful)}")
        print(f"  Average: {sum(durations)/len(durations):.1f}ms")
        print(f"  < 100ms: {sum(1 for d in durations if d < 100)}/{len(successful)}")
        print(f"  < 500ms: {sum(1 for d in durations if d < 500)}/{len(successful)}")

print("\n" + "="*80)
print(f"✓ Results saved to: {result_file}")
print("="*80)
