#!/usr/bin/env python3
"""
Query Benchmark Runner
Executes query test suite and measures performance
"""

import os
import sys
import time
from pathlib import Path
import clickhouse_connect
from datetime import datetime
import json


class BenchmarkRunner:
    def __init__(self):
        # ClickHouse connection
        self.host = os.getenv('CLICKHOUSE_HOST')
        self.port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
        self.user = os.getenv('CLICKHOUSE_USER', 'default')
        self.password = os.getenv('CLICKHOUSE_PASSWORD')
        self.database = os.getenv('CLICKHOUSE_DATABASE', 'device360')

        if not all([self.host, self.password]):
            print("ERROR: Missing CLICKHOUSE_HOST or CLICKHOUSE_PASSWORD")
            sys.exit(1)

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
            print(f"✗ Failed to connect: {e}")
            sys.exit(1)

        self.results = []

    def get_sample_device_id(self):
        """Get a sample device ID with significant activity"""
        try:
            query = """
            SELECT device_id, count() as cnt
            FROM device360.ad_requests
            WHERE event_date >= today() - 7
            GROUP BY device_id
            HAVING cnt > 100
            ORDER BY cnt DESC
            LIMIT 1
            """
            result = self.client.query(query)
            if result.result_rows:
                device_id = result.result_rows[0][0]
                print(f"Using sample device_id: {device_id}")
                return device_id
            else:
                print("Warning: No suitable device_id found, using placeholder")
                return "00000000-0000-0000-0000-000000000000"
        except Exception as e:
            print(f"Warning: Could not fetch sample device_id: {e}")
            return "00000000-0000-0000-0000-000000000000"

    def parse_sql_file(self, filepath):
        """Parse SQL file into individual queries"""
        with open(filepath, 'r') as f:
            content = f.read()

        queries = []
        current_query = []
        current_comment = []

        for line in content.split('\n'):
            stripped = line.strip()

            # Track comments
            if stripped.startswith('--'):
                current_comment.append(stripped[2:].strip())
            elif stripped and not stripped.startswith('--'):
                current_query.append(line)
            elif current_query and stripped == '':
                # Empty line might indicate query end
                continue

            # Detect query end (semicolon)
            if stripped.endswith(';'):
                if current_query:
                    query_text = '\n'.join(current_query)
                    query_name = current_comment[0] if current_comment else f"Query {len(queries) + 1}"

                    # Extract test name from comment
                    test_name = query_name
                    if query_name.startswith('Test '):
                        test_name = query_name.split(':')[0] if ':' in query_name else query_name

                    queries.append({
                        'name': test_name,
                        'description': ' '.join(current_comment),
                        'sql': query_text.rstrip(';')
                    })

                    current_query = []
                    current_comment = []

        return queries

    def execute_query(self, query_sql, query_name):
        """Execute a query and measure performance"""
        try:
            # Replace placeholder device_id if present
            if 'e68bfaae-4981-4f64-b67b-0108daa2f896' in query_sql:
                sample_id = self.get_sample_device_id()
                query_sql = query_sql.replace('e68bfaae-4981-4f64-b67b-0108daa2f896', sample_id)

            # Execute query
            start_time = time.time()
            result = self.client.query(query_sql)
            elapsed_ms = (time.time() - start_time) * 1000

            return {
                'success': True,
                'duration_ms': elapsed_ms,
                'rows_returned': len(result.result_rows),
                'error': None
            }

        except Exception as e:
            return {
                'success': False,
                'duration_ms': 0,
                'rows_returned': 0,
                'error': str(e)
            }

    def run_query_file(self, filepath):
        """Run all queries in a file"""
        print(f"\n{'='*60}")
        print(f"Running: {filepath.name}")
        print('='*60)

        queries = self.parse_sql_file(filepath)
        print(f"Found {len(queries)} queries")

        file_results = []

        for idx, query in enumerate(queries, 1):
            print(f"\n[{idx}/{len(queries)}] {query['name']}")
            print(f"  Description: {query['description'][:80]}...")

            result = self.execute_query(query['sql'], query['name'])

            if result['success']:
                print(f"  ✓ Duration: {result['duration_ms']:.1f}ms")
                print(f"  ✓ Rows: {result['rows_returned']}")
            else:
                print(f"  ✗ Error: {result['error'][:100]}")

            query_result = {
                'file': filepath.name,
                'query_name': query['name'],
                'description': query['description'],
                'duration_ms': result['duration_ms'],
                'rows_returned': result['rows_returned'],
                'success': result['success'],
                'error': result['error'],
                'timestamp': datetime.now().isoformat()
            }

            file_results.append(query_result)
            self.results.append(query_result)

        return file_results

    def run_all_benchmarks(self):
        """Run all query files"""
        queries_dir = Path(__file__).parent.parent / 'queries'

        if not queries_dir.exists():
            print(f"ERROR: Queries directory not found: {queries_dir}")
            sys.exit(1)

        query_files = sorted(queries_dir.glob('*.sql'))

        if not query_files:
            print(f"ERROR: No SQL files found in {queries_dir}")
            sys.exit(1)

        print("="*60)
        print("Device360 Query Benchmark Suite")
        print("="*60)
        print(f"Query files: {len(query_files)}")
        print(f"Database: {self.database}")
        print("="*60)

        for query_file in query_files:
            self.run_query_file(query_file)

        self.print_summary()
        self.save_results()

    def print_summary(self):
        """Print benchmark summary"""
        print("\n" + "="*60)
        print("Benchmark Summary")
        print("="*60)

        total_queries = len(self.results)
        successful = sum(1 for r in self.results if r['success'])
        failed = total_queries - successful

        print(f"Total queries: {total_queries}")
        print(f"Successful: {successful}")
        print(f"Failed: {failed}")

        if successful > 0:
            successful_results = [r for r in self.results if r['success']]
            durations = [r['duration_ms'] for r in successful_results]

            print(f"\nPerformance:")
            print(f"  Average: {sum(durations) / len(durations):.1f}ms")
            print(f"  Median: {sorted(durations)[len(durations)//2]:.1f}ms")
            print(f"  Min: {min(durations):.1f}ms")
            print(f"  Max: {max(durations):.1f}ms")

            # Performance targets
            print(f"\nTarget Achievement:")
            under_100ms = sum(1 for d in durations if d < 100)
            under_500ms = sum(1 for d in durations if d < 500)
            under_1s = sum(1 for d in durations if d < 1000)
            under_3s = sum(1 for d in durations if d < 3000)

            print(f"  < 100ms: {under_100ms}/{successful} ({under_100ms*100//successful}%)")
            print(f"  < 500ms: {under_500ms}/{successful} ({under_500ms*100//successful}%)")
            print(f"  < 1s: {under_1s}/{successful} ({under_1s*100//successful}%)")
            print(f"  < 3s: {under_3s}/{successful} ({under_3s*100//successful}%)")

            # Top 5 slowest queries
            print(f"\nSlowest Queries:")
            slowest = sorted(successful_results, key=lambda x: x['duration_ms'], reverse=True)[:5]
            for i, r in enumerate(slowest, 1):
                print(f"  {i}. {r['query_name']}: {r['duration_ms']:.1f}ms")

        print("="*60)

    def save_results(self):
        """Save results to JSON file"""
        output_dir = Path(__file__).parent.parent / 'results'
        output_dir.mkdir(exist_ok=True)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = output_dir / f'benchmark_results_{timestamp}.json'

        with open(output_file, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'database': self.database,
                'host': self.host,
                'results': self.results
            }, f, indent=2)

        print(f"\nResults saved to: {output_file}")


def main():
    try:
        runner = BenchmarkRunner()
        runner.run_all_benchmarks()
    except KeyboardInterrupt:
        print("\n\nBenchmark interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
