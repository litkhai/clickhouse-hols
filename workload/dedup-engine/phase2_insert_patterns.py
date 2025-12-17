#!/usr/bin/env python3
"""
Phase 2: Insert 패턴별 성능 테스트
목적: Row-by-row vs Batch insert의 성능 차이를 측정
"""

import time
from config import TestConfig
from utils import DataGenerator, ClickHouseClient, print_header, print_results_table

# DDL 정의
DDL_TEMPLATE = """
CREATE TABLE IF NOT EXISTS dedup.{table_name} (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String,
    _version UInt64 DEFAULT toUInt64(now64(3))
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product)
"""

class Phase2Tester:
    """Phase 2 테스터"""

    def __init__(self, client: ClickHouseClient, config: TestConfig):
        self.client = client
        self.config = config

    def setup_tables(self):
        """테이블 생성"""
        print("\n[Phase 2] 테이블 생성")

        tables = ['p2_row_by_row', 'p2_micro_batch', 'p2_batch', 'p2_async_insert']
        for table_name in tables:
            ddl = DDL_TEMPLATE.format(table_name=table_name)
            self.client.execute_ddl(ddl, f"{table_name} 테이블 생성")

    def cleanup_tables(self):
        """테이블 초기화"""
        print("\n[Phase 2] 테이블 초기화")
        tables = ['p2_row_by_row', 'p2_micro_batch', 'p2_batch', 'p2_async_insert']
        for table in tables:
            self.client.truncate_table(f"dedup.{table}")
        print("  ✓ 모든 테이블 초기화 완료")

    def test_row_by_row(self, records, limit=1000):
        """Row-by-row insert 테스트"""
        table = 'dedup.p2_row_by_row'
        print(f"\n  [1/4] Row-by-row insert (limit: {limit})")

        start = time.time()
        for i, r in enumerate(records[:limit]):
            sql = f"""INSERT INTO {table}
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES ('{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}')"""
            self.client.client.command(sql)

            if (i + 1) % 100 == 0:
                print(f"    진행: {i + 1}/{limit} ({(i+1)/limit*100:.0f}%)")

        elapsed = time.time() - start
        count = self.client.get_count(table, use_final=True)
        print(f"    완료: {elapsed:.2f}초, {limit/elapsed:.1f} rows/sec, Final count: {count}")

        return {
            'method': 'row_by_row',
            'records': limit,
            'elapsed': elapsed,
            'rate': limit / elapsed,
            'final_count': count
        }

    def test_micro_batch(self, records, batch_size=100, limit=10000):
        """Micro-batch insert 테스트"""
        table = 'dedup.p2_micro_batch'
        print(f"\n  [2/4] Micro-batch insert (batch: {batch_size}, limit: {limit})")

        columns = ['timestamp', 'account', 'product', 'metric_value',
                  'metric_count', 'category', 'region', 'status',
                  'description', 'extra_data']

        start = time.time()
        for i in range(0, min(limit, len(records)), batch_size):
            batch = records[i:i + batch_size]
            data = [[r.timestamp, r.account, r.product, r.metric_value,
                     r.metric_count, r.category, r.region, r.status,
                     r.description, r.extra_data] for r in batch]
            self.client.client.insert(table, data, column_names=columns)

            if (i + batch_size) % 1000 == 0:
                print(f"    진행: {i + batch_size}/{limit} ({(i+batch_size)/limit*100:.0f}%)")

        elapsed = time.time() - start
        count = self.client.get_count(table, use_final=True)
        print(f"    완료: {elapsed:.2f}초, {limit/elapsed:.1f} rows/sec, Final count: {count}")

        return {
            'method': 'micro_batch',
            'records': limit,
            'elapsed': elapsed,
            'rate': limit / elapsed,
            'final_count': count
        }

    def test_batch(self, records, limit=10000):
        """Batch insert 테스트"""
        table = 'dedup.p2_batch'
        print(f"\n  [3/4] Batch insert (limit: {limit})")

        columns = ['timestamp', 'account', 'product', 'metric_value',
                  'metric_count', 'category', 'region', 'status',
                  'description', 'extra_data']

        data = [[r.timestamp, r.account, r.product, r.metric_value,
                 r.metric_count, r.category, r.region, r.status,
                 r.description, r.extra_data] for r in records[:limit]]

        start = time.time()
        self.client.client.insert(table, data, column_names=columns)
        elapsed = time.time() - start

        count = self.client.get_count(table, use_final=True)
        print(f"    완료: {elapsed:.2f}초, {limit/elapsed:.1f} rows/sec, Final count: {count}")

        return {
            'method': 'batch',
            'records': limit,
            'elapsed': elapsed,
            'rate': limit / elapsed,
            'final_count': count
        }

    def test_async_insert(self, records, limit=1000):
        """Async insert 테스트"""
        table = 'dedup.p2_async_insert'
        print(f"\n  [4/4] Async insert (limit: {limit})")

        # Async insert 설정
        self.client.client.command("SET async_insert = 1")
        self.client.client.command("SET wait_for_async_insert = 0")

        start = time.time()
        for i, r in enumerate(records[:limit]):
            sql = f"""INSERT INTO {table}
                (timestamp, account, product, metric_value, metric_count,
                 category, region, status, description, extra_data)
                VALUES ('{r.timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}',
                    '{r.account}', '{r.product}', {r.metric_value},
                    {r.metric_count}, '{r.category}', '{r.region}',
                    '{r.status}', '{r.description}', '{r.extra_data}')"""
            self.client.client.command(sql)

            if (i + 1) % 100 == 0:
                print(f"    진행: {i + 1}/{limit} ({(i+1)/limit*100:.0f}%)")

        elapsed = time.time() - start

        # Async insert가 완료될 때까지 대기
        print(f"    Async insert 완료 대기 중...")
        time.sleep(5)

        # Async insert 설정 해제
        self.client.client.command("SET async_insert = 0")

        count = self.client.get_count(table, use_final=True)
        print(f"    완료: {elapsed:.2f}초, {limit/elapsed:.1f} rows/sec, Final count: {count}")

        return {
            'method': 'async_insert',
            'records': limit,
            'elapsed': elapsed,
            'rate': limit / elapsed,
            'final_count': count
        }

    def print_results(self, results):
        """결과 출력"""
        print("\n[Phase 2] 테스트 결과")

        headers = ['Method', 'Records', 'Time (s)', 'Rate (rows/s)', 'Final Count']
        rows = [
            [
                r['method'],
                f"{r['records']:,}",
                f"{r['elapsed']:.2f}",
                f"{r['rate']:.0f}",
                f"{r['final_count']:,}"
            ]
            for r in results
        ]

        print_results_table(headers, rows)

        # 성능 비교
        print("\n성능 비교:")
        baseline = results[0]['rate']  # row_by_row를 baseline으로
        for r in results:
            improvement = (r['rate'] / baseline - 1) * 100
            print(f"  {r['method']:<15}: {r['rate']:>8.0f} rows/sec ({improvement:+6.1f}%)")

def run_phase2():
    """Phase 2 실행"""
    print_header("Phase 2: Insert 패턴별 성능 테스트")

    # Config 및 Client 초기화
    config = TestConfig()
    client = ClickHouseClient(config)
    tester = Phase2Tester(client, config)

    # 테이블 생성
    tester.setup_tables()
    tester.cleanup_tables()

    # 테스트 데이터 생성
    generator = DataGenerator(config)
    records, _ = generator.generate()

    # 테스트 실행
    print("\n[Phase 2] 테스트 시작")
    results = []

    results.append(tester.test_row_by_row(records, limit=1000))
    results.append(tester.test_micro_batch(records, batch_size=100, limit=10000))
    results.append(tester.test_batch(records, limit=10000))
    results.append(tester.test_async_insert(records, limit=1000))

    # 결과 출력
    tester.print_results(results)

    print("\n✓ Phase 2 테스트 완료")
    return results

if __name__ == '__main__':
    try:
        run_phase2()
    except Exception as e:
        print(f"\n✗ 에러 발생: {e}")
        import traceback
        traceback.print_exc()
