#!/usr/bin/env python3
"""
Phase 3: 권장 아키텍처 검증
목적: Landing → Main → Refreshable MV 아키텍처 검증
"""

import time
from config import TestConfig
from utils import DataGenerator, ClickHouseClient, print_header, print_results_table

# DDL 정의
DDL_LANDING = """
CREATE TABLE IF NOT EXISTS dedup.p3_landing (
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
    _insert_time DateTime64(3) DEFAULT now64(3)
) ENGINE = MergeTree()
ORDER BY (timestamp, account, product)
TTL toDateTime(_insert_time) + INTERVAL 1 HOUR
"""

DDL_MAIN = """
CREATE TABLE IF NOT EXISTS dedup.p3_main (
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
    _version UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (timestamp, account, product)
"""

DDL_MV = """
CREATE MATERIALIZED VIEW IF NOT EXISTS dedup.p3_landing_to_main_mv TO dedup.p3_main AS
SELECT
    timestamp, account, product, metric_value, metric_count,
    category, region, status, description, extra_data,
    toUInt64(now64(3)) as _version
FROM dedup.p3_landing
"""

DDL_HOURLY_AGG = """
CREATE MATERIALIZED VIEW IF NOT EXISTS dedup.p3_hourly_agg
REFRESH EVERY 1 MINUTE
ENGINE = MergeTree()
ORDER BY (hour, account, category)
AS SELECT
    toStartOfHour(timestamp) as hour,
    account,
    category,
    count() as event_count,
    uniq(timestamp, product) as unique_events,
    sum(metric_value) as total_metric_value
FROM dedup.p3_main FINAL
GROUP BY hour, account, category
"""

class Phase3Tester:
    """Phase 3 테스터"""

    def __init__(self, client: ClickHouseClient, config: TestConfig):
        self.client = client
        self.config = config

    def setup_tables(self):
        """테이블 생성"""
        print("\n[Phase 3] 테이블 생성")

        ddls = [
            (DDL_LANDING, "p3_landing 테이블"),
            (DDL_MAIN, "p3_main 테이블"),
            (DDL_MV, "p3_landing_to_main_mv MV"),
            (DDL_HOURLY_AGG, "p3_hourly_agg Refreshable MV"),
        ]

        for ddl, desc in ddls:
            self.client.execute_ddl(ddl, f"{desc} 생성")

    def cleanup_tables(self):
        """테이블 초기화"""
        print("\n[Phase 3] 테이블 초기화")

        # MV 먼저 삭제
        try:
            self.client.client.command("DROP VIEW IF EXISTS dedup.p3_hourly_agg")
            self.client.client.command("DROP VIEW IF EXISTS dedup.p3_landing_to_main_mv")
        except:
            pass

        # 테이블 삭제
        tables = ['p3_main', 'p3_landing']
        for table in tables:
            try:
                self.client.client.command(f"DROP TABLE IF EXISTS dedup.{table}")
            except:
                pass

        print("  ✓ 모든 테이블/뷰 삭제 완료")

    def insert_to_landing(self, records, batch_size=1000):
        """Landing 테이블에 데이터 insert"""
        table = 'dedup.p3_landing'
        columns = ['timestamp', 'account', 'product', 'metric_value',
                  'metric_count', 'category', 'region', 'status',
                  'description', 'extra_data']

        print(f"\n  Landing 테이블에 데이터 insert 중...")
        start = time.time()

        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            data = [[r.timestamp, r.account, r.product, r.metric_value,
                     r.metric_count, r.category, r.region, r.status,
                     r.description, r.extra_data] for r in batch]
            self.client.client.insert(table, data, column_names=columns)

            if (i + batch_size) % 5000 == 0:
                print(f"    진행: {i + batch_size}/{len(records)}")

        elapsed = time.time() - start
        print(f"  ✓ Insert 완료: {elapsed:.2f}초")
        return elapsed

    def verify_pipeline(self, expected_unique):
        """파이프라인 검증"""
        print("\n[Phase 3] 파이프라인 데이터 검증")

        # 약간 대기 (MV 처리)
        print("  MV 처리 대기 (5초)...")
        time.sleep(5)

        # Landing count
        landing = self.client.get_count('dedup.p3_landing')

        # Main count
        main_raw = self.client.get_count('dedup.p3_main')
        main_final = self.client.get_count('dedup.p3_main', use_final=True)

        # Refreshable MV 강제 refresh
        print("  Refreshable MV 강제 refresh...")
        try:
            self.client.client.command("SYSTEM REFRESH VIEW dedup.p3_hourly_agg")
            time.sleep(5)
        except Exception as e:
            print(f"    주의: Refresh 실패 - {e}")

        # Hourly aggregation count
        try:
            hourly_count = self.client.get_count('dedup.p3_hourly_agg')
        except:
            hourly_count = 0

        # 결과
        results = {
            'landing': landing,
            'main_raw': main_raw,
            'main_final': main_final,
            'hourly_agg': hourly_count,
            'expected': expected_unique
        }

        headers = ['항목', '레코드 수', '비고']
        rows = [
            ['Landing', f"{results['landing']:,}", '원본 데이터'],
            ['Main (Raw)', f"{results['main_raw']:,}", 'MV로 전달된 데이터'],
            ['Main (FINAL)', f"{results['main_final']:,}", 'Dedup 후 데이터'],
            ['Hourly Agg', f"{results['hourly_agg']:,}", 'Refreshable MV'],
            ['Expected Unique', f"{results['expected']:,}", '목표값']
        ]

        print_results_table(headers, rows)

        # 검증
        print("\n검증 결과:")
        if results['main_final'] == expected_unique:
            print("  ✅ Main FINAL = Expected Unique")
        else:
            diff = results['main_final'] - expected_unique
            print(f"  ⚠️  Main FINAL ≠ Expected (차이: {diff})")

        if results['main_raw'] > results['main_final']:
            print("  ✅ Main에서 Dedup 동작 확인")
        else:
            print("  ⚠️  Main에서 Dedup 미동작")

        return results

def run_phase3():
    """Phase 3 실행"""
    print_header("Phase 3: 권장 아키텍처 검증")

    # Config 및 Client 초기화
    config = TestConfig()
    client = ClickHouseClient(config)
    tester = Phase3Tester(client, config)

    # 기존 테이블 정리 및 새로 생성
    tester.cleanup_tables()
    tester.setup_tables()

    # 테스트 데이터 생성
    generator = DataGenerator(config)
    records, expected_unique = generator.generate()

    # Landing에 데이터 insert
    print("\n[Phase 3] 테스트 시작")
    print(f"  총 레코드: {len(records)}, 예상 Unique: {expected_unique}")
    tester.insert_to_landing(records)

    # 파이프라인 검증
    results = tester.verify_pipeline(expected_unique)

    print("\n✓ Phase 3 테스트 완료")
    return results

if __name__ == '__main__':
    try:
        run_phase3()
    except Exception as e:
        print(f"\n✗ 에러 발생: {e}")
        import traceback
        traceback.print_exc()
