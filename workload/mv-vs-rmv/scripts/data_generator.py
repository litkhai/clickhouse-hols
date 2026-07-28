#!/usr/bin/env python3
"""
MV vs RMV 테스트: 데이터 생성 스크립트
Data Generator Script for MV vs RMV Test

30분간 1초당 1,000 rows를 ClickHouse에 INSERT
Insert 1,000 rows per second to ClickHouse for 30 minutes
"""

import os
import time
import random
import uuid
from datetime import datetime
import clickhouse_connect

# 설정 — 접속 정보는 환경변수로 주입합니다 (scripts/.env.example 참고)
# Connection settings are injected via environment variables (see scripts/.env.example)
HOST = os.environ.get('CH_HOST', '')
PASSWORD = os.environ.get('CH_PASSWORD', '')
USER = os.environ.get('CH_USER', 'default')
DATABASE = os.environ.get('CH_DATABASE', 'mv_vs_rmv')

if not HOST or not PASSWORD:
    raise SystemExit(
        'CH_HOST / CH_PASSWORD 환경변수를 설정하세요. 예:\n'
        "  export CH_HOST='<your-service>.<region>.aws.clickhouse.cloud'\n"
        "  export CH_PASSWORD='...'"
    )
TABLE = 'events_source'

# 테스트 설정
ROWS_PER_BATCH = 1000  # 1초당 삽입할 행 수
DURATION_MINUTES = 30  # 테스트 지속 시간 (분)
TOTAL_BATCHES = DURATION_MINUTES * 60  # 총 배치 수

# 샘플 데이터
EVENT_TYPES = ['pageview', 'click', 'purchase', 'signup', 'logout']
COUNTRIES = ['KR', 'US', 'JP', 'CN', 'DE', 'FR', 'GB', 'AU']
DEVICE_TYPES = ['mobile', 'desktop', 'tablet']


def generate_batch_data(batch_size):
    """
    배치 크기만큼의 랜덤 데이터 생성
    Generate random data for a batch
    """
    data = []
    for _ in range(batch_size):
        row = (
            random.randint(1, 100000),  # user_id
            random.choice(EVENT_TYPES),  # event_type
            f'/page/{random.randint(1, 1000)}',  # page_url
            str(uuid.uuid4()),  # session_id
            random.choice(COUNTRIES),  # country
            random.choice(DEVICE_TYPES),  # device_type
            round(random.uniform(0, 100), 2),  # revenue
            random.randint(1, 10)  # quantity
        )
        data.append(row)
    return data


def main():
    """
    메인 실행 함수
    Main execution function
    """
    print(f"=" * 80)
    print(f"MV vs RMV Test - Data Generator")
    print(f"=" * 80)
    print(f"Host: {HOST}")
    print(f"Database: {DATABASE}")
    print(f"Table: {TABLE}")
    print(f"Rows per batch: {ROWS_PER_BATCH}")
    print(f"Duration: {DURATION_MINUTES} minutes")
    print(f"Total batches: {TOTAL_BATCHES}")
    print(f"Expected total rows: ~{ROWS_PER_BATCH * TOTAL_BATCHES:,}")
    print(f"=" * 80)
    print()

    # ClickHouse 연결
    try:
        client = clickhouse_connect.get_client(
            host=HOST,
            secure=True,
            username=USER,
            password=PASSWORD,
            database=DATABASE
        )
        print("✅ Connected to ClickHouse Cloud")

        # 연결 테스트
        result = client.query("SELECT version()")
        version = result.result_rows[0][0]
        print(f"✅ ClickHouse version: {version}")
        print()

    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return

    # 데이터 생성 및 삽입
    start_time = time.time()
    total_rows_inserted = 0

    print(f"🚀 Starting data generation at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Press Ctrl+C to stop early")
    print()

    try:
        for batch_num in range(1, TOTAL_BATCHES + 1):
            batch_start = time.time()

            # 데이터 생성
            batch_data = generate_batch_data(ROWS_PER_BATCH)

            # ClickHouse에 삽입
            try:
                client.insert(
                    table=TABLE,
                    data=batch_data,
                    column_names=['user_id', 'event_type', 'page_url', 'session_id',
                                  'country', 'device_type', 'revenue', 'quantity']
                )
                total_rows_inserted += ROWS_PER_BATCH

                # 진행 상황 출력 (10초마다)
                if batch_num % 10 == 0:
                    elapsed_time = time.time() - start_time
                    rows_per_sec = total_rows_inserted / elapsed_time
                    progress = (batch_num / TOTAL_BATCHES) * 100
                    remaining_minutes = ((TOTAL_BATCHES - batch_num) / 60)

                    print(f"[{batch_num:4d}/{TOTAL_BATCHES}] "
                          f"Progress: {progress:5.1f}% | "
                          f"Rows: {total_rows_inserted:,} | "
                          f"Rate: {rows_per_sec:,.0f} rows/sec | "
                          f"Remaining: {remaining_minutes:.1f} min")

            except Exception as e:
                print(f"❌ Batch {batch_num} insert failed: {e}")
                continue

            # 1초 주기 유지 (배치 처리 시간 고려)
            batch_duration = time.time() - batch_start
            sleep_time = max(0, 1.0 - batch_duration)
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print()
        print(f"⚠️  Interrupted by user")

    finally:
        # 최종 통계
        end_time = time.time()
        total_duration = end_time - start_time
        avg_rows_per_sec = total_rows_inserted / total_duration if total_duration > 0 else 0

        print()
        print(f"=" * 80)
        print(f"📊 Final Statistics")
        print(f"=" * 80)
        print(f"Total rows inserted: {total_rows_inserted:,}")
        print(f"Total duration: {total_duration:.1f} seconds ({total_duration/60:.1f} minutes)")
        print(f"Average rate: {avg_rows_per_sec:,.0f} rows/sec")
        print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"=" * 80)

        # 테이블 확인
        try:
            result = client.query(f"SELECT count() FROM {TABLE}")
            row_count = result.result_rows[0][0]
            print(f"✅ Table {TABLE} now has {row_count:,} rows")
        except Exception as e:
            print(f"❌ Failed to query table: {e}")

        client.close()
        print(f"✅ Connection closed")


if __name__ == '__main__':
    main()
