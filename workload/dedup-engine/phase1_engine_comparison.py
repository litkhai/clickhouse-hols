#!/usr/bin/env python3
"""
Phase 1: Engine 비교 테스트
목적: 동일한 중복 데이터에 대해 각 Table Engine의 deduplication 동작 방식과 효과를 비교
"""

import time
from config import TestConfig
from utils import DataGenerator, ClickHouseClient, print_header, print_results_table

# DDL 정의
DDL_BASELINE = """
CREATE TABLE IF NOT EXISTS dedup.p1_baseline (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value Float64,
    metric_count UInt64,
    category LowCardinality(String),
    region LowCardinality(String),
    status LowCardinality(String),
    description String,
    extra_data String
) ENGINE = MergeTree()
ORDER BY (timestamp, account, product)
"""

DDL_REPLACING = """
CREATE TABLE IF NOT EXISTS dedup.p1_replacing (
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

DDL_COLLAPSING = """
CREATE TABLE IF NOT EXISTS dedup.p1_collapsing (
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
    sign Int8 DEFAULT 1
) ENGINE = CollapsingMergeTree(sign)
ORDER BY (timestamp, account, product)
"""

DDL_AGGREGATING = """
CREATE TABLE IF NOT EXISTS dedup.p1_aggregating (
    timestamp DateTime64(3),
    account String,
    product String,
    metric_value SimpleAggregateFunction(any, Float64),
    metric_count SimpleAggregateFunction(any, UInt64),
    category SimpleAggregateFunction(any, String),
    region SimpleAggregateFunction(any, String),
    status SimpleAggregateFunction(any, String),
    description SimpleAggregateFunction(any, String),
    extra_data SimpleAggregateFunction(any, String)
) ENGINE = AggregatingMergeTree()
ORDER BY (timestamp, account, product)
"""

class Phase1Tester:
    """Phase 1 테스터"""

    def __init__(self, client: ClickHouseClient, config: TestConfig):
        self.client = client
        self.config = config

    def setup_tables(self):
        """테이블 생성"""
        print("\n[Phase 1] 테이블 생성")

        # Database 생성
        self.client.execute_ddl(
            "CREATE DATABASE IF NOT EXISTS dedup",
            "Database 생성"
        )

        # 테이블 생성
        tables = [
            (DDL_BASELINE, "p1_baseline"),
            (DDL_REPLACING, "p1_replacing"),
            (DDL_COLLAPSING, "p1_collapsing"),
            (DDL_AGGREGATING, "p1_aggregating"),
        ]

        for ddl, table_name in tables:
            self.client.execute_ddl(ddl, f"{table_name} 테이블 생성")

    def cleanup_tables(self):
        """테이블 초기화"""
        print("\n[Phase 1] 테이블 초기화")
        tables = ['p1_baseline', 'p1_replacing', 'p1_collapsing', 'p1_aggregating']
        for table in tables:
            self.client.truncate_table(f"dedup.{table}")
        print("  ✓ 모든 테이블 초기화 완료")

    def run_test(self, records, expected_unique):
        """테스트 실행"""
        print(f"\n[Phase 1] 테스트 시작")
        print(f"  총 레코드: {len(records)}, 예상 Unique: {expected_unique}")

        tables = [
            ('dedup.p1_baseline', 'MergeTree'),
            ('dedup.p1_replacing', 'ReplacingMT'),
            ('dedup.p1_collapsing', 'CollapsingMT'),
            ('dedup.p1_aggregating', 'AggregatingMT'),
        ]

        results = []

        for table, engine in tables:
            print(f"\n  Testing {table}...")

            # 데이터 insert
            elapsed = self.client.insert_batch(table, records)
            print(f"    Insert 완료: {elapsed:.2f}초 ({len(records)/elapsed:.0f} rows/sec)")

            # Raw count
            raw_count = self.client.get_count(table)

            # Dedup count
            if engine in ['ReplacingMT', 'CollapsingMT', 'AggregatingMT']:
                dedup_count = self.client.get_count(table, use_final=True)
            else:
                # baseline은 DISTINCT 사용
                dedup_count = self.client.client.command(
                    f"SELECT count(DISTINCT (timestamp, account, product)) FROM {table}"
                )

            # OPTIMIZE 실행
            print(f"    OPTIMIZE 실행 중...")
            self.client.optimize_table(table)
            time.sleep(2)

            # OPTIMIZE 후 count
            after_optimize = self.client.get_count(table)

            # 결과 저장
            result = {
                'engine': engine,
                'raw_count': raw_count,
                'dedup_count': dedup_count,
                'after_optimize': after_optimize,
                'insert_time': elapsed,
                'dedup_success': '✅' if after_optimize == expected_unique else '❌'
            }
            results.append(result)

            print(f"    Raw: {raw_count}, Dedup: {dedup_count}, After Optimize: {after_optimize}")

        return results

    def print_results(self, results, expected_unique):
        """결과 출력"""
        print(f"\n[Phase 1] 테스트 결과 (예상 Unique: {expected_unique})")

        headers = ['Engine', 'Raw Count', 'Dedup Count', 'After OPTIMIZE', 'Insert Time', 'Success']
        rows = [
            [
                r['engine'],
                r['raw_count'],
                r['dedup_count'],
                r['after_optimize'],
                f"{r['insert_time']:.2f}s",
                r['dedup_success']
            ]
            for r in results
        ]

        print_results_table(headers, rows)

        # 평가
        print("\n평가:")
        for r in results:
            if r['engine'] == 'MergeTree':
                print(f"  {r['engine']}: 중복 유지 (예상된 동작)")
            elif r['dedup_success'] == '✅':
                print(f"  {r['engine']}: ✅ Dedup 성공")
            else:
                if r['engine'] == 'CollapsingMT':
                    print(f"  {r['engine']}: ❌ Sign 관리 필요 (단순 insert로는 중복 제거 안됨)")
                else:
                    print(f"  {r['engine']}: ❌ Dedup 실패")

def run_phase1():
    """Phase 1 실행"""
    print_header("Phase 1: Engine 비교 테스트")

    # Config 및 Client 초기화
    config = TestConfig()
    client = ClickHouseClient(config)
    tester = Phase1Tester(client, config)

    # 테이블 생성
    tester.setup_tables()
    tester.cleanup_tables()

    # 테스트 데이터 생성
    generator = DataGenerator(config)
    records, expected_unique = generator.generate()

    # 테스트 실행
    results = tester.run_test(records, expected_unique)

    # 결과 출력
    tester.print_results(results, expected_unique)

    print("\n✓ Phase 1 테스트 완료")
    return results

if __name__ == '__main__':
    try:
        run_phase1()
    except Exception as e:
        print(f"\n✗ 에러 발생: {e}")
        import traceback
        traceback.print_exc()
