#!/usr/bin/env python3
"""
MV vs RMV 테스트: 테스트 실행 메인 스크립트
Main Test Execution Script for MV vs RMV Test

테스트 세션 생성, 데이터 생성, 모니터링 수집을 통합 실행
Integrated execution of test session creation, data generation, and monitoring
"""

import subprocess
import time
import sys
from datetime import datetime
import clickhouse_connect

# 설정
HOST = '<your-service>.<region>.aws.clickhouse.cloud'
PASSWORD = '<YOUR_PASSWORD>'
DATABASE = 'mv_vs_rmv'
TEST_DESCRIPTION = 'MV vs RMV 30분 비교 테스트 - Automated Run'


def create_test_session(client):
    """테스트 세션 생성"""
    print(f"📝 Creating test session...")

    query = f"""
    INSERT INTO {DATABASE}.test_sessions (test_type, description)
    VALUES ('BOTH_TEST', '{TEST_DESCRIPTION}')
    """
    try:
        client.command(query)
        print(f"✅ Test session created")

        # 생성된 session_id 조회
        result = client.query(f"""
            SELECT session_id, start_time
            FROM {DATABASE}.test_sessions
            ORDER BY start_time DESC
            LIMIT 1
        """)
        if result.result_rows:
            session_id, start_time = result.result_rows[0]
            print(f"✅ Session ID: {session_id}")
            print(f"   Start time: {start_time}")
            return str(session_id)
        else:
            print(f"❌ Failed to retrieve session ID")
            return None

    except Exception as e:
        print(f"❌ Failed to create test session: {e}")
        return None


def verify_mv_rmv_status(client):
    """MV/RMV 상태 확인"""
    print(f"🔍 Verifying MV/RMV status...")

    try:
        # MV 확인
        result = client.query(f"""
            SELECT name, engine
            FROM system.tables
            WHERE database = '{DATABASE}'
              AND name IN ('events_mv_realtime', 'events_rmv_batch')
            ORDER BY name
        """)

        if len(result.result_rows) == 2:
            print(f"✅ MV and RMV found:")
            for name, engine in result.result_rows:
                print(f"   - {name}: {engine}")
        else:
            print(f"❌ MV or RMV not found")
            return False

        # RMV refresh 상태 확인
        result = client.query(f"""
            SELECT status, last_success_time, next_refresh_time
            FROM system.view_refreshes
            WHERE database = '{DATABASE}' AND view = 'events_rmv_batch'
        """)

        if result.result_rows:
            status, last_success, next_refresh = result.result_rows[0]
            print(f"✅ RMV Refresh Status:")
            print(f"   - Status: {status}")
            print(f"   - Last success: {last_success}")
            print(f"   - Next refresh: {next_refresh}")
            return True
        else:
            print(f"❌ RMV refresh status not found")
            return False

    except Exception as e:
        print(f"❌ Failed to verify MV/RMV status: {e}")
        return False


def verify_tables_empty(client):
    """테이블이 비어있는지 확인"""
    print(f"🔍 Verifying tables are empty...")

    tables = ['events_source', 'events_agg_mv', 'events_agg_rmv']
    all_empty = True

    try:
        for table in tables:
            result = client.query(f"SELECT count() FROM {DATABASE}.{table}")
            count = result.result_rows[0][0]
            if count > 0:
                print(f"⚠️  {table} has {count:,} rows")
                all_empty = False
            else:
                print(f"✅ {table} is empty")

        return all_empty

    except Exception as e:
        print(f"❌ Failed to verify tables: {e}")
        return False


def end_test_session(client, session_id):
    """테스트 세션 종료 마킹"""
    print(f"📝 Ending test session {session_id}...")

    query = f"""
    ALTER TABLE {DATABASE}.test_sessions
    UPDATE end_time = now64(3)
    WHERE session_id = '{session_id}'
    """
    try:
        client.command(query)
        print(f"✅ Test session ended")
        return True
    except Exception as e:
        print(f"❌ Failed to end test session: {e}")
        return False


def main():
    """메인 실행 함수"""
    print(f"=" * 80)
    print(f"MV vs RMV Test - Main Test Runner")
    print(f"=" * 80)
    print(f"Host: {HOST}")
    print(f"Database: {DATABASE}")
    print(f"Description: {TEST_DESCRIPTION}")
    print(f"=" * 80)
    print()

    # ClickHouse 연결
    try:
        client = clickhouse_connect.get_client(
            host=HOST,
            secure=True,
            password=PASSWORD,
            database=DATABASE
        )
        print("✅ Connected to ClickHouse Cloud")

        # 버전 확인
        result = client.query("SELECT version()")
        version = result.result_rows[0][0]
        print(f"✅ ClickHouse version: {version}")
        print()

    except Exception as e:
        print(f"❌ Connection failed: {e}")
        sys.exit(1)

    # Step 1: MV/RMV 상태 확인
    if not verify_mv_rmv_status(client):
        print(f"❌ MV/RMV status check failed. Please check your setup.")
        sys.exit(1)
    print()

    # Step 2: 테이블이 비어있는지 확인
    if not verify_tables_empty(client):
        response = input("⚠️  Tables are not empty. Do you want to continue? (yes/no): ")
        if response.lower() != 'yes':
            print(f"❌ Test aborted by user")
            sys.exit(1)
    print()

    # Step 3: 테스트 세션 생성
    session_id = create_test_session(client)
    if not session_id:
        print(f"❌ Failed to create test session")
        sys.exit(1)
    print()

    # ClickHouse 연결 종료 (subprocess에서 새로 연결하므로)
    client.close()

    # Step 4: 데이터 생성 및 모니터링 프로세스 시작
    print(f"🚀 Starting data generation and monitoring...")
    print(f"=" * 80)
    print()

    # 데이터 생성 프로세스 (백그라운드)
    data_gen_process = subprocess.Popen(
        ['python3', 'data_generator.py'],
        cwd='/Users/kenlee/Documents/GitHub/clickhouse-hols/workload/mv-vs-rmv/scripts'
    )
    print(f"✅ Data generator started (PID: {data_gen_process.pid})")

    # 잠시 대기 (데이터 생성 시작 확인)
    time.sleep(5)

    # 모니터링 수집 프로세스 (백그라운드)
    monitoring_process = subprocess.Popen(
        ['python3', 'monitoring_collector.py', session_id],
        cwd='/Users/kenlee/Documents/GitHub/clickhouse-hols/workload/mv-vs-rmv/scripts'
    )
    print(f"✅ Monitoring collector started (PID: {monitoring_process.pid})")
    print()

    # 프로세스 완료 대기
    try:
        print(f"⏳ Waiting for data generation to complete...")
        print(f"   (This will take approximately 30 minutes)")
        print(f"   Press Ctrl+C to stop early")
        print()

        data_gen_process.wait()
        print(f"✅ Data generation completed")

        # 모니터링도 종료
        print(f"⏳ Stopping monitoring collector...")
        monitoring_process.terminate()
        monitoring_process.wait(timeout=10)
        print(f"✅ Monitoring collector stopped")

    except KeyboardInterrupt:
        print()
        print(f"⚠️  Interrupted by user")
        print(f"⏳ Stopping processes...")

        # 프로세스 종료
        data_gen_process.terminate()
        monitoring_process.terminate()

        data_gen_process.wait(timeout=10)
        monitoring_process.wait(timeout=10)

        print(f"✅ Processes stopped")

    finally:
        # 테스트 세션 종료 마킹
        print()
        print(f"📝 Finalizing test session...")

        client = clickhouse_connect.get_client(
            host=HOST,
            secure=True,
            password=PASSWORD,
            database=DATABASE
        )

        end_test_session(client, session_id)

        # 최종 통계
        print()
        print(f"=" * 80)
        print(f"📊 Final Statistics")
        print(f"=" * 80)

        tables = ['events_source', 'events_agg_mv', 'events_agg_rmv']
        for table in tables:
            try:
                result = client.query(f"SELECT count() FROM {DATABASE}.{table}")
                count = result.result_rows[0][0]
                print(f"{table}: {count:,} rows")
            except Exception as e:
                print(f"{table}: Error - {e}")

        print(f"=" * 80)
        print()
        print(f"✅ Test completed!")
        print(f"   Session ID: {session_id}")
        print(f"   Use this session ID for result analysis")
        print()

        client.close()


if __name__ == '__main__':
    main()
