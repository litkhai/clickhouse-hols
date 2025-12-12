#!/usr/bin/env python3
"""
Scale Test Runner for Device360 PoC
Tests ingestion and query performance across different vCPU configurations
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

# Load .env file
def load_env():
    env_file = Path(__file__).parent.parent / '.env'
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

load_env()


class ScaleTestRunner:
    def __init__(self):
        # ClickHouse connection
        self.host = os.getenv('CLICKHOUSE_HOST')
        self.port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
        self.user = os.getenv('CLICKHOUSE_USER', 'default')
        self.password = os.getenv('CLICKHOUSE_PASSWORD')
        self.database = os.getenv('CLICKHOUSE_DATABASE', 'device360')

        # CHC API credentials
        self.chc_key_id = os.getenv('CHC_KEY_ID')
        self.chc_key_secret = os.getenv('CHC_KEY_SECRET')
        self.chc_service_id = os.getenv('CHC_SERVICE_ID')

        # S3 configuration
        self.bucket_name = os.getenv('S3_BUCKET_NAME')
        self.s3_prefix = 'device360'

        # Test configurations
        self.vcpu_configs = [8, 16, 24]
        self.test_results = []

        # Initialize ClickHouse client
        try:
            self.client = clickhouse_connect.get_client(
                host=self.host,
                port=self.port,
                user=self.user,
                password=self.password,
                secure=True
            )
            print(f"✓ Connected to ClickHouse: {self.host}")
        except Exception as e:
            print(f"✗ Failed to connect to ClickHouse: {e}")
            sys.exit(1)

    def scale_service(self, vcpu_count):
        """Scale ClickHouse service to specified vCPU count"""
        print(f"\n{'='*60}")
        print(f"Scaling service to {vcpu_count} vCPU...")
        print('='*60)

        # CHC API endpoint
        url = f"https://api.clickhouse.cloud/v1/organizations/{os.getenv('CHC_ORG_ID')}/services/{self.chc_service_id}"

        headers = {
            'Content-Type': 'application/json'
        }

        payload = {
            "minTotalMemoryGb": vcpu_count * 2,  # 2GB RAM per vCPU
            "maxTotalMemoryGb": vcpu_count * 2
        }

        try:
            response = requests.patch(
                url,
                auth=HTTPBasicAuth(self.chc_key_id, self.chc_key_secret),
                headers=headers,
                json=payload
            )

            if response.status_code in [200, 202]:
                print(f"✓ Service scaling initiated to {vcpu_count} vCPU")

                # Wait for scaling to complete
                print("Waiting for scaling to complete...")
                time.sleep(60)  # Wait 1 minute for scaling

                # Verify scaling
                verify_response = requests.get(
                    url,
                    auth=HTTPBasicAuth(self.chc_key_id, self.chc_key_secret)
                )

                if verify_response.status_code == 200:
                    service_info = verify_response.json()
                    print(f"✓ Current configuration: {service_info.get('minTotalMemoryGb', 'unknown')}GB RAM")

                return True
            else:
                print(f"✗ Failed to scale service: {response.status_code}")
                print(response.text)
                return False

        except Exception as e:
            print(f"✗ Error scaling service: {e}")
            return False

    def drop_database(self):
        """Drop device360 database to start fresh"""
        print("\nDropping existing database...")
        try:
            self.client.command(f"DROP DATABASE IF EXISTS {self.database}")
            print(f"✓ Database '{self.database}' dropped")
            time.sleep(5)  # Wait for drop to complete
            return True
        except Exception as e:
            print(f"✗ Failed to drop database: {e}")
            return False

    def create_schema(self):
        """Create database and tables"""
        print("\nCreating schema...")

        sql_dir = Path(__file__).parent.parent / 'sql'

        try:
            for sql_file in sorted(sql_dir.glob('*.sql')):
                print(f"  Executing {sql_file.name}...")
                with open(sql_file, 'r') as f:
                    sql = f.read()

                    statements = [s.strip() for s in sql.split(';') if s.strip() and not s.strip().startswith('--')]

                    for statement in statements:
                        try:
                            self.client.command(statement)
                        except Exception as e:
                            print(f"    Warning: {e}")

            print("✓ Schema created successfully")
            return True
        except Exception as e:
            print(f"✗ Failed to create schema: {e}")
            return False

    def get_s3_files(self):
        """Get list of S3 files to ingest"""
        import boto3

        s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION'))

        try:
            response = s3_client.list_objects_v2(
                Bucket=self.bucket_name,
                Prefix=self.s3_prefix
            )

            if 'Contents' not in response:
                print(f"No files found in s3://{self.bucket_name}/{self.s3_prefix}/")
                return []

            files = [obj['Key'] for obj in response['Contents'] if obj['Key'].endswith('.json.gz')]
            return sorted(files)

        except Exception as e:
            print(f"✗ Failed to list S3 files: {e}")
            return []

    def ingest_data(self, vcpu_count):
        """Ingest data and measure performance"""
        print(f"\n{'='*60}")
        print(f"Data Ingestion Test - {vcpu_count} vCPU")
        print('='*60)

        # Get S3 files
        files = self.get_s3_files()

        if not files:
            print("✗ No files to ingest")
            return None

        print(f"Found {len(files)} files to ingest")

        total_rows = 0
        total_bytes = 0
        start_time = time.time()
        file_stats = []

        for idx, s3_key in enumerate(files, 1):
            file_name = s3_key.split('/')[-1]
            print(f"[{idx}/{len(files)}] Ingesting {file_name}...")

            file_start = time.time()

            try:
                # Build INSERT query
                s3_url = f"https://{self.bucket_name}.s3.{os.getenv('AWS_REGION')}.amazonaws.com/{s3_key}"

                query = f"""
                INSERT INTO {self.database}.ad_requests
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
                FROM s3(
                    '{s3_url}',
                    '{os.getenv("AWS_ACCESS_KEY_ID")}',
                    '{os.getenv("AWS_SECRET_ACCESS_KEY")}',
                    'JSONEachRow'
                )
                SETTINGS input_format_import_nested_json = 1
                """

                self.client.command(query)

                file_elapsed = time.time() - file_start

                # Get current row count
                current_rows = self.client.command(f"SELECT count() FROM {self.database}.ad_requests")
                rows_in_file = current_rows - total_rows
                total_rows = current_rows

                rows_per_sec = rows_in_file / file_elapsed if file_elapsed > 0 else 0

                print(f"  ✓ {rows_in_file:,} rows in {file_elapsed:.1f}s ({rows_per_sec:,.0f} rows/s)")

                file_stats.append({
                    'file': file_name,
                    'rows': rows_in_file,
                    'duration_sec': file_elapsed,
                    'rows_per_sec': rows_per_sec
                })

            except Exception as e:
                print(f"  ✗ Failed: {e}")
                continue

        total_elapsed = time.time() - start_time
        avg_rows_per_sec = total_rows / total_elapsed if total_elapsed > 0 else 0

        result = {
            'vcpu_count': vcpu_count,
            'total_rows': total_rows,
            'total_duration_sec': total_elapsed,
            'avg_rows_per_sec': avg_rows_per_sec,
            'files_ingested': len(file_stats),
            'file_stats': file_stats
        }

        print(f"\n{'='*60}")
        print(f"Ingestion Complete - {vcpu_count} vCPU")
        print('='*60)
        print(f"Total rows: {total_rows:,}")
        print(f"Total time: {total_elapsed:.1f}s ({total_elapsed/60:.1f} minutes)")
        print(f"Average rate: {avg_rows_per_sec:,.0f} rows/s")
        print('='*60)

        return result

    def run_benchmarks(self, vcpu_count):
        """Run query benchmarks"""
        print(f"\n{'='*60}")
        print(f"Query Benchmark Test - {vcpu_count} vCPU")
        print('='*60)

        queries_dir = Path(__file__).parent.parent / 'queries'
        query_files = sorted(queries_dir.glob('*.sql'))

        benchmark_results = []

        for query_file in query_files:
            print(f"\nRunning queries from {query_file.name}...")

            # Parse and execute queries
            queries = self._parse_sql_file(query_file)

            for query in queries:
                print(f"  {query['name'][:60]}...")

                try:
                    start_time = time.time()
                    result = self.client.query(query['sql'])
                    elapsed_ms = (time.time() - start_time) * 1000

                    print(f"    ✓ {elapsed_ms:.1f}ms ({len(result.result_rows)} rows)")

                    benchmark_results.append({
                        'query_name': query['name'],
                        'file': query_file.name,
                        'duration_ms': elapsed_ms,
                        'rows_returned': len(result.result_rows),
                        'success': True
                    })

                except Exception as e:
                    print(f"    ✗ Error: {str(e)[:60]}")
                    benchmark_results.append({
                        'query_name': query['name'],
                        'file': query_file.name,
                        'duration_ms': 0,
                        'rows_returned': 0,
                        'success': False,
                        'error': str(e)
                    })

        # Calculate summary statistics
        successful = [r for r in benchmark_results if r['success']]

        if successful:
            durations = [r['duration_ms'] for r in successful]
            summary = {
                'vcpu_count': vcpu_count,
                'total_queries': len(benchmark_results),
                'successful_queries': len(successful),
                'failed_queries': len(benchmark_results) - len(successful),
                'avg_duration_ms': sum(durations) / len(durations),
                'median_duration_ms': sorted(durations)[len(durations)//2],
                'min_duration_ms': min(durations),
                'max_duration_ms': max(durations),
                'under_100ms': sum(1 for d in durations if d < 100),
                'under_500ms': sum(1 for d in durations if d < 500),
                'under_1s': sum(1 for d in durations if d < 1000),
                'under_3s': sum(1 for d in durations if d < 3000),
                'queries': benchmark_results
            }
        else:
            summary = {
                'vcpu_count': vcpu_count,
                'total_queries': len(benchmark_results),
                'successful_queries': 0,
                'failed_queries': len(benchmark_results),
                'queries': benchmark_results
            }

        print(f"\n{'='*60}")
        print(f"Benchmark Summary - {vcpu_count} vCPU")
        print('='*60)
        if successful:
            print(f"Successful: {len(successful)}/{len(benchmark_results)}")
            print(f"Average: {summary['avg_duration_ms']:.1f}ms")
            print(f"Median: {summary['median_duration_ms']:.1f}ms")
            print(f"< 100ms: {summary['under_100ms']}/{len(successful)}")
            print(f"< 500ms: {summary['under_500ms']}/{len(successful)}")
            print(f"< 1s: {summary['under_1s']}/{len(successful)}")
        print('='*60)

        return summary

    def _parse_sql_file(self, filepath):
        """Parse SQL file into individual queries"""
        with open(filepath, 'r') as f:
            content = f.read()

        queries = []
        current_query = []
        current_comment = []

        for line in content.split('\n'):
            stripped = line.strip()

            if stripped.startswith('--'):
                current_comment.append(stripped[2:].strip())
            elif stripped and not stripped.startswith('--'):
                current_query.append(line)

            if stripped.endswith(';'):
                if current_query:
                    query_text = '\n'.join(current_query)
                    query_name = current_comment[0] if current_comment else f"Query {len(queries) + 1}"

                    if query_name.startswith('Test '):
                        query_name = query_name.split(':')[0] if ':' in query_name else query_name

                    queries.append({
                        'name': query_name,
                        'sql': query_text.rstrip(';')
                    })

                    current_query = []
                    current_comment = []

        return queries

    def run_scale_tests(self):
        """Run complete scale test suite"""
        print("="*60)
        print("Device360 Scale Test Suite")
        print("="*60)
        print(f"vCPU configurations: {self.vcpu_configs}")
        print(f"Database: {self.database}")
        print(f"Service: {self.host}")
        print("="*60)

        all_results = []

        for vcpu_count in self.vcpu_configs:
            test_start = time.time()

            print(f"\n\n{'#'*60}")
            print(f"# TEST: {vcpu_count} vCPU Configuration")
            print(f"{'#'*60}")

            # Scale service
            if not self.scale_service(vcpu_count):
                print(f"✗ Failed to scale to {vcpu_count} vCPU, skipping...")
                continue

            # Drop and recreate database
            if not self.drop_database():
                print(f"✗ Failed to drop database, skipping...")
                continue

            # Create schema
            if not self.create_schema():
                print(f"✗ Failed to create schema, skipping...")
                continue

            # Run ingestion test
            ingestion_result = self.ingest_data(vcpu_count)

            if not ingestion_result:
                print(f"✗ Ingestion failed for {vcpu_count} vCPU")
                continue

            # Run query benchmarks (only after 24 vCPU ingestion)
            if vcpu_count == 24:
                benchmark_result = self.run_benchmarks(vcpu_count)
            else:
                benchmark_result = None

            test_elapsed = time.time() - test_start

            test_result = {
                'vcpu_count': vcpu_count,
                'test_duration_sec': test_elapsed,
                'ingestion': ingestion_result,
                'benchmarks': benchmark_result,
                'timestamp': datetime.now().isoformat()
            }

            all_results.append(test_result)

            # Save intermediate results
            self._save_results(all_results)

        # Print final summary
        self._print_final_summary(all_results)

        return all_results

    def _save_results(self, results):
        """Save results to JSON file"""
        output_dir = Path(__file__).parent.parent / 'results'
        output_dir.mkdir(exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = output_dir / f'scale_test_results_{timestamp}.json'

        with open(output_file, 'w') as f:
            json.dump({
                'test_date': datetime.now().isoformat(),
                'service_id': self.chc_service_id,
                'host': self.host,
                'database': self.database,
                'results': results
            }, f, indent=2)

        print(f"\n✓ Results saved to: {output_file}")

    def _print_final_summary(self, results):
        """Print comprehensive summary"""
        print("\n\n")
        print("="*80)
        print("FINAL SCALE TEST SUMMARY")
        print("="*80)

        print("\nIngestion Performance:")
        print("-"*80)
        print(f"{'vCPU':<10} {'Total Rows':<15} {'Duration':<15} {'Rows/sec':<20} {'Improvement'}")
        print("-"*80)

        baseline_rate = None
        for result in results:
            if 'ingestion' in result and result['ingestion']:
                ing = result['ingestion']
                rate = ing['avg_rows_per_sec']

                if baseline_rate is None:
                    baseline_rate = rate
                    improvement = "Baseline"
                else:
                    improvement = f"{rate / baseline_rate:.2f}x"

                print(f"{ing['vcpu_count']:<10} {ing['total_rows']:<15,} "
                      f"{ing['total_duration_sec']:<15.1f} {rate:<20,.0f} {improvement}")

        print("-"*80)

        # Query performance summary (from 24 vCPU test)
        bench_result = next((r['benchmarks'] for r in results if r.get('benchmarks')), None)

        if bench_result:
            print("\nQuery Performance (24 vCPU):")
            print("-"*80)
            print(f"Total queries: {bench_result['total_queries']}")
            print(f"Successful: {bench_result['successful_queries']}")
            print(f"Average duration: {bench_result.get('avg_duration_ms', 0):.1f}ms")
            print(f"Median duration: {bench_result.get('median_duration_ms', 0):.1f}ms")
            print(f"\nPerformance targets:")
            print(f"  < 100ms: {bench_result.get('under_100ms', 0)}/{bench_result['successful_queries']}")
            print(f"  < 500ms: {bench_result.get('under_500ms', 0)}/{bench_result['successful_queries']}")
            print(f"  < 1s: {bench_result.get('under_1s', 0)}/{bench_result['successful_queries']}")
            print("-"*80)

        print("="*80)


def main():
    try:
        runner = ScaleTestRunner()
        results = runner.run_scale_tests()
        print("\n✓ Scale test suite completed successfully")

    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
