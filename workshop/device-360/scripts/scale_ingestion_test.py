#!/usr/bin/env python3
"""
Device360 Scale Ingestion Test
Tests ingestion performance at different vCPU scales (8, 16, 24)
Estimates 300GB ingestion time based on 30GB results
"""

import subprocess
import time
import json
from datetime import datetime

# ClickHouse connection info
CH_HOST = "a7rzc4b3c1.ap-northeast-2.aws.clickhouse.cloud"
CH_USER = "default"
CH_PASSWORD = "HTPiB0FXg8.3K"
CH_ORG_ID = "9142daed-a43f-455a-a112-f721d02b80af"
CH_API_KEY_ID = "mMyJAi9HVaIS90Y04AMv"
CH_API_KEY_SECRET = "4b1dL38QfbjIiVqP4TxfYhbGd6ParymSUJdOGtvD1Y"
CH_SERVICE_ID = "c5ccc996-e105-4f61-aa12-4769ea485f7f"

# Test configuration
S3_URL = "https://device360-test-orangeaws.s3.ap-northeast-2.amazonaws.com/device360/*.json.gz"
DATA_SIZE_GB = 28.56
CHUNK_COUNT = 224
TARGET_SIZE_GB = 300

# vCPU scales to test
VCPU_SCALES = [
    {"name": "Small", "vcpu": 8, "memory_gb": 32, "runs": 3},
    {"name": "Medium", "vcpu": 16, "memory_gb": 64, "runs": 3},
    {"name": "Large", "vcpu": 24, "memory_gb": 96, "runs": 3}
]

print("=" * 100)
print("Device360 Scale Ingestion Test")
print("=" * 100)
print(f"Data Size: {DATA_SIZE_GB} GB ({CHUNK_COUNT} chunks)")
print(f"Target Projection: {TARGET_SIZE_GB} GB")
print(f"S3 Location: s3://device360-test-orangeaws/device360/")
print("=" * 100)
print()

def run_clickhouse_query(query, timeout=600):
    """Execute ClickHouse query and return result"""
    cmd = [
        "clickhouse", "client",
        f"--host={CH_HOST}",
        f"--user={CH_USER}",
        f"--password={CH_PASSWORD}",
        "--secure",
        f"--query={query}",
        "--time",
        "--progress"
    ]

    start_time = time.time()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        elapsed = time.time() - start_time

        return {
            "success": result.returncode == 0,
            "elapsed": elapsed,
            "stdout": result.stdout,
            "stderr": result.stderr
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "elapsed": timeout,
            "error": "Timeout"
        }

def get_current_scale():
    """Get current service scale from ClickHouse Cloud"""
    query = "SELECT value FROM system.settings WHERE name = 'max_threads'"
    result = run_clickhouse_query(query)
    if result["success"]:
        threads = int(result["stdout"].strip())
        return threads
    return None

def scale_service(vcpu_count):
    """Scale ClickHouse Cloud service (using API)"""
    # Note: This requires ClickHouse Cloud API implementation
    # For now, we'll prompt user to scale manually
    print(f"\n{'='*100}")
    print(f"⚠️  MANUAL SCALING REQUIRED")
    print(f"{'='*100}")
    print(f"Please scale the service to {vcpu_count} vCPU using ClickHouse Cloud Console:")
    print(f"  https://console.clickhouse.cloud/services/{CH_SERVICE_ID}")
    print(f"{'='*100}")
    input(f"Press ENTER after scaling to {vcpu_count} vCPU...")

    # Verify scaling
    current = get_current_scale()
    print(f"Current max_threads: {current}")
    print()

def clear_table():
    """Clear ad_requests table"""
    print("Clearing table...")
    query = "TRUNCATE TABLE device360.ad_requests"
    result = run_clickhouse_query(query, timeout=30)
    if result["success"]:
        print("✓ Table cleared")
    else:
        print(f"✗ Failed to clear table: {result.get('stderr', 'Unknown error')}")
        return False

    # Verify empty
    query = "SELECT count(*) FROM device360.ad_requests"
    result = run_clickhouse_query(query, timeout=10)
    if result["success"]:
        count = int(result["stdout"].strip())
        print(f"  Row count: {count}")
        if count != 0:
            print("  ⚠️  Warning: Table not empty!")
            return False

    # Wait for cleanup
    print("  Waiting 10s for cleanup...")
    time.sleep(10)
    print()
    return True

def run_ingestion_test(scale_config, run_number):
    """Run single ingestion test"""
    vcpu = scale_config["vcpu"]
    scale_name = scale_config["name"]

    print(f"\n{'='*100}")
    print(f"Test: {scale_name} ({vcpu} vCPU) - Run {run_number}")
    print(f"{'='*100}")

    # Prepare query
    query = f"""
    INSERT INTO device360.ad_requests
    SELECT * FROM s3(
        '{S3_URL}',
        'JSONEachRow'
    )
    SETTINGS max_insert_threads={min(vcpu, 32)}, max_insert_block_size=1000000, s3_max_connections={min(vcpu * 4, 64)}
    """

    print(f"Starting ingestion at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}...")
    print(f"Settings:")
    print(f"  - max_insert_threads: {min(vcpu, 32)}")
    print(f"  - max_insert_block_size: 1,000,000")
    print(f"  - s3_max_connections: {min(vcpu * 4, 64)}")
    print()

    # Run ingestion
    result = run_clickhouse_query(query, timeout=3600)

    if result["success"]:
        elapsed = result["elapsed"]
        throughput = DATA_SIZE_GB / (elapsed / 60)  # GB/min
        estimated_300gb = (TARGET_SIZE_GB / DATA_SIZE_GB) * elapsed / 60  # minutes

        print(f"\n✓ Ingestion completed!")
        print(f"{'='*100}")
        print(f"Results:")
        print(f"  Elapsed Time: {elapsed:.2f} seconds ({elapsed/60:.2f} minutes)")
        print(f"  Data Size: {DATA_SIZE_GB} GB")
        print(f"  Throughput: {throughput:.2f} GB/min")
        print(f"  Estimated 300GB Time: {estimated_300gb:.2f} minutes ({estimated_300gb/60:.2f} hours)")
        print(f"{'='*100}")

        # Get stderr for progress info
        if result["stderr"]:
            print("\nProgress output:")
            print(result["stderr"][-1000:])  # Last 1000 chars

        # Verify row count
        query = "SELECT count(*) as total, formatReadableSize(sum(bytes_on_disk)) as disk_size FROM device360.ad_requests"
        verify = run_clickhouse_query(query, timeout=30)
        if verify["success"]:
            print("\nTable Statistics:")
            print(verify["stdout"])

        return {
            "success": True,
            "vcpu": vcpu,
            "scale_name": scale_name,
            "run": run_number,
            "elapsed_sec": elapsed,
            "elapsed_min": elapsed / 60,
            "throughput_gb_min": throughput,
            "estimated_300gb_min": estimated_300gb,
            "estimated_300gb_hours": estimated_300gb / 60
        }
    else:
        print(f"\n✗ Ingestion failed!")
        print(f"Error: {result.get('stderr', 'Unknown error')}")
        return {
            "success": False,
            "vcpu": vcpu,
            "scale_name": scale_name,
            "run": run_number,
            "error": result.get("stderr", "Unknown error")
        }

def main():
    results = []

    for scale_config in VCPU_SCALES:
        vcpu = scale_config["vcpu"]
        runs = scale_config["runs"]
        scale_name = scale_config["name"]

        print(f"\n\n{'#'*100}")
        print(f"# SCALE TEST: {scale_name} ({vcpu} vCPU)")
        print(f"{'#'*100}")

        # Scale service
        scale_service(vcpu)

        # Run multiple tests
        scale_results = []
        for run in range(1, runs + 1):
            # Clear table before each run
            if not clear_table():
                print(f"Failed to clear table, skipping run {run}")
                continue

            # Run test
            result = run_ingestion_test(scale_config, run)
            results.append(result)
            scale_results.append(result)

            # Wait between runs
            if run < runs:
                print(f"\nWaiting 30 seconds before next run...")
                time.sleep(30)

        # Calculate scale statistics
        successful = [r for r in scale_results if r["success"]]
        if successful:
            avg_time = sum(r["elapsed_sec"] for r in successful) / len(successful)
            avg_throughput = sum(r["throughput_gb_min"] for r in successful) / len(successful)
            avg_300gb_estimate = sum(r["estimated_300gb_min"] for r in successful) / len(successful)

            print(f"\n{'='*100}")
            print(f"Scale Summary: {scale_name} ({vcpu} vCPU)")
            print(f"{'='*100}")
            print(f"Successful Runs: {len(successful)}/{runs}")
            print(f"Average Time: {avg_time:.2f} sec ({avg_time/60:.2f} min)")
            print(f"Average Throughput: {avg_throughput:.2f} GB/min")
            print(f"Average 300GB Estimate: {avg_300gb_estimate:.2f} min ({avg_300gb_estimate/60:.2f} hours)")
            print(f"{'='*100}")

    # Final summary
    print(f"\n\n{'#'*100}")
    print(f"# FINAL SUMMARY")
    print(f"{'#'*100}")
    print(f"\nTest Configuration:")
    print(f"  Data Size: {DATA_SIZE_GB} GB")
    print(f"  Chunk Count: {CHUNK_COUNT}")
    print(f"  Target Projection: {TARGET_SIZE_GB} GB")
    print()

    # Group by scale
    for scale_config in VCPU_SCALES:
        vcpu = scale_config["vcpu"]
        scale_name = scale_config["name"]
        scale_results = [r for r in results if r["vcpu"] == vcpu and r["success"]]

        if scale_results:
            avg_time = sum(r["elapsed_min"] for r in scale_results) / len(scale_results)
            avg_throughput = sum(r["throughput_gb_min"] for r in scale_results) / len(scale_results)
            avg_300gb = sum(r["estimated_300gb_hours"] for r in scale_results) / len(scale_results)

            print(f"\n{scale_name} ({vcpu} vCPU):")
            print(f"  {'Run':<6} {'Time (min)':<15} {'Throughput (GB/min)':<25} {'Est. 300GB (hours)'}")
            print(f"  {'-'*6} {'-'*15} {'-'*25} {'-'*20}")

            for r in scale_results:
                print(f"  {r['run']:<6} {r['elapsed_min']:>13.2f}   {r['throughput_gb_min']:>22.2f}   {r['estimated_300gb_hours']:>18.2f}")

            print(f"  {'AVG':<6} {avg_time:>13.2f}   {avg_throughput:>22.2f}   {avg_300gb:>18.2f}")

    # Save results
    output_file = f"/Users/kenlee/Documents/GitHub/clickhouse-hols/workshop/device-360/results/scale_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(output_file, 'w') as f:
        json.dump({
            "test_date": datetime.now().isoformat(),
            "data_size_gb": DATA_SIZE_GB,
            "target_size_gb": TARGET_SIZE_GB,
            "chunk_count": CHUNK_COUNT,
            "results": results
        }, f, indent=2)

    print(f"\n\nResults saved to: {output_file}")
    print(f"{'#'*100}\n")

if __name__ == "__main__":
    main()
