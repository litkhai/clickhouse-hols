#!/usr/bin/env python3
"""
S3 to ClickHouse Ingestion Script
Loads data from S3 with parallel ingestion and performance monitoring
"""

import os
import sys
import time
from datetime import datetime
import clickhouse_connect
import boto3
from pathlib import Path


class ClickHouseIngestion:
    def __init__(self):
        # ClickHouse connection
        self.host = os.getenv('CLICKHOUSE_HOST')
        self.port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
        self.user = os.getenv('CLICKHOUSE_USER', 'default')
        self.password = os.getenv('CLICKHOUSE_PASSWORD')
        self.database = os.getenv('CLICKHOUSE_DATABASE', 'device360')

        # S3 configuration
        self.bucket_name = os.getenv('S3_BUCKET_NAME')
        self.s3_prefix = 'device360'
        self.role_arn = os.getenv('S3_ROLE_ARN')
        self.aws_region = os.getenv('AWS_REGION', 'us-east-1')

        # Validate configuration
        if not all([self.host, self.password, self.bucket_name]):
            print("ERROR: Missing required environment variables")
            print("Required: CLICKHOUSE_HOST, CLICKHOUSE_PASSWORD, S3_BUCKET_NAME")
            sys.exit(1)

        # Initialize clients
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

        self.s3_client = boto3.client('s3', region_name=self.aws_region)

    def get_s3_files(self):
        """List all data files in S3"""
        try:
            response = self.s3_client.list_objects_v2(
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

    def setup_schema(self):
        """Create database and tables"""
        print("\nSetting up schema...")

        sql_dir = Path(__file__).parent.parent / 'sql'

        # Execute DDL scripts in order
        for sql_file in sorted(sql_dir.glob('*.sql')):
            print(f"  Executing {sql_file.name}...")
            with open(sql_file, 'r') as f:
                sql = f.read()

                # Split by semicolon and execute each statement
                statements = [s.strip() for s in sql.split(';') if s.strip() and not s.strip().startswith('--')]

                for statement in statements:
                    try:
                        self.client.command(statement)
                    except Exception as e:
                        print(f"    Warning: {e}")

        print("✓ Schema setup complete")

    def ingest_single_file_s3_function(self, s3_key):
        """Ingest a single file using ClickHouse s3 table function"""
        s3_url = f"s3://{self.bucket_name}/{s3_key}"

        # Build INSERT query using s3 table function
        if self.role_arn:
            # Use IAM role authentication
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
                'JSONEachRow',
                'auto'
            )
            SETTINGS input_format_import_nested_json = 1
            """
        else:
            # Use AWS credentials
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

        return query

    def ingest_files(self, files, parallel_jobs=1):
        """Ingest files from S3 to ClickHouse"""
        print(f"\nStarting ingestion of {len(files)} files...")
        print(f"Parallel jobs: {parallel_jobs}")
        print("="*60)

        total_rows = 0
        total_time = 0
        ingestion_stats = []

        for idx, s3_key in enumerate(files, 1):
            file_name = s3_key.split('/')[-1]
            print(f"[{idx}/{len(files)}] Ingesting {file_name}...")

            start_time = time.time()

            try:
                query = self.ingest_single_file_s3_function(s3_key)
                self.client.command(query)

                # Get row count for this file
                rows_query = f"""
                SELECT count() FROM {self.database}.ad_requests
                WHERE event_date >= today() - 60
                """
                current_rows = self.client.command(rows_query)

                elapsed = time.time() - start_time
                rows_in_file = current_rows - total_rows
                total_rows = current_rows

                rate = rows_in_file / elapsed if elapsed > 0 else 0

                print(f"  ✓ Ingested {rows_in_file:,} rows in {elapsed:.1f}s ({rate:,.0f} rows/s)")

                ingestion_stats.append({
                    'file': file_name,
                    'rows': rows_in_file,
                    'time': elapsed,
                    'rate': rate
                })

                total_time += elapsed

            except Exception as e:
                print(f"  ✗ Failed to ingest {file_name}: {e}")
                continue

        return total_rows, total_time, ingestion_stats

    def verify_ingestion(self):
        """Verify data was ingested correctly"""
        print("\nVerifying ingestion...")

        checks = [
            ("Total rows", f"SELECT count() FROM {self.database}.ad_requests"),
            ("Unique devices", f"SELECT uniq(device_id) FROM {self.database}.ad_requests"),
            ("Date range", f"SELECT min(event_date), max(event_date) FROM {self.database}.ad_requests"),
            ("Sample device", f"SELECT device_id, count() as cnt FROM {self.database}.ad_requests GROUP BY device_id ORDER BY cnt DESC LIMIT 1")
        ]

        for check_name, query in checks:
            try:
                result = self.client.query(query)
                print(f"  {check_name}: {result.result_rows[0]}")
            except Exception as e:
                print(f"  ✗ {check_name} check failed: {e}")

    def print_summary(self, total_rows, total_time, stats):
        """Print ingestion summary"""
        print("\n" + "="*60)
        print("Ingestion Complete!")
        print("="*60)
        print(f"Total rows ingested: {total_rows:,}")
        print(f"Total time: {total_time:.1f} seconds")
        print(f"Average rate: {total_rows / total_time:,.0f} rows/s" if total_time > 0 else "N/A")
        print(f"Files processed: {len(stats)}")

        if stats:
            avg_rate = sum(s['rate'] for s in stats) / len(stats)
            print(f"Average file ingestion rate: {avg_rate:,.0f} rows/s")

        print("="*60)

    def run(self):
        """Execute complete ingestion workflow"""
        print("="*60)
        print("Device360 S3 to ClickHouse Ingestion")
        print("="*60)
        print(f"Source: s3://{self.bucket_name}/{self.s3_prefix}/")
        print(f"Target: {self.host}/{self.database}")
        print("="*60)

        # Setup schema
        self.setup_schema()

        # Get S3 files
        files = self.get_s3_files()

        if not files:
            print("No files to ingest")
            return

        print(f"\nFound {len(files)} files to ingest")

        # Calculate total size
        total_size = 0
        for f in files:
            try:
                response = self.s3_client.head_object(Bucket=self.bucket_name, Key=f)
                total_size += response['ContentLength']
            except:
                pass

        print(f"Total size: {total_size / (1024**3):.2f} GB")

        # Confirm ingestion
        confirm = input("\nProceed with ingestion? (yes/no): ").strip().lower()
        if confirm != 'yes':
            print("Ingestion cancelled")
            return

        # Run ingestion
        start_time = time.time()
        total_rows, total_time, stats = self.ingest_files(files)

        # Verify
        self.verify_ingestion()

        # Print summary
        self.print_summary(total_rows, total_time, stats)


def main():
    try:
        ingestion = ClickHouseIngestion()
        ingestion.run()
    except KeyboardInterrupt:
        print("\n\nIngestion interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
