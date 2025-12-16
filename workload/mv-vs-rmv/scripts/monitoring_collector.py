#!/usr/bin/env python3
"""
MV vs RMV 테스트: 모니터링 데이터 수집 스크립트
Monitoring Data Collection Script for MV vs RMV Test

1분마다 리소스 메트릭, Part 히스토리, Merge 활동 수집
Collect resource metrics, part history, and merge activity every minute
"""

import time
import sys
from datetime import datetime
import clickhouse_connect

# 설정
HOST = 'a7rzc4b3c1.ap-northeast-2.aws.clickhouse.cloud'
PASSWORD = 'HTPiB0FXg8.3K'
DATABASE = 'mv_vs_rmv'

# 모니터링 설정
COLLECTION_INTERVAL = 60  # 초 (1분)


def collect_parts_history(client, session_id):
    """Part 상태 수집"""
    query = f"""
    INSERT INTO {DATABASE}.parts_history
    SELECT
        now64(3) AS collected_at,
        '{session_id}' AS session_id,
        table AS table_name,
        partition,
        count() AS part_count,
        sum(rows) AS row_count,
        sum(bytes_on_disk) AS bytes_on_disk,
        countIf(active) AS active_parts,
        countIf(NOT active) AS inactive_parts
    FROM system.parts
    WHERE database = '{DATABASE}'
      AND table IN ('events_source', 'events_agg_mv', 'events_agg_rmv')
    GROUP BY table, partition
    """
    try:
        client.command(query)
        return True
    except Exception as e:
        print(f"❌ Part history collection failed: {e}")
        return False


def collect_query_metrics_mv(client, session_id):
    """MV 관련 쿼리 메트릭 수집"""
    query = f"""
    INSERT INTO {DATABASE}.resource_metrics
    SELECT
        now64(3) AS collected_at,
        '{session_id}' AS session_id,
        count() AS query_count,
        sum(query_duration_ms) AS query_duration_ms,
        sum(memory_usage) AS memory_usage_bytes,
        max(memory_usage) AS peak_memory_usage_bytes,
        sum(read_rows) AS read_rows,
        sum(read_bytes) AS read_bytes,
        sum(written_rows) AS written_rows,
        sum(written_bytes) AS written_bytes,
        0 AS merge_count,
        0 AS parts_count,
        'MV' AS metric_source
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 1 MINUTE
      AND type = 'QueryFinish'
      AND (query LIKE '%events_agg_mv%' OR query LIKE '%events_mv_realtime%')
      AND query NOT LIKE '%system%'
      AND query NOT LIKE '%resource_metrics%'
    """
    try:
        client.command(query)
        return True
    except Exception as e:
        print(f"❌ MV metrics collection failed: {e}")
        return False


def collect_query_metrics_rmv(client, session_id):
    """RMV 관련 쿼리 메트릭 수집"""
    query = f"""
    INSERT INTO {DATABASE}.resource_metrics
    SELECT
        now64(3) AS collected_at,
        '{session_id}' AS session_id,
        count() AS query_count,
        sum(query_duration_ms) AS query_duration_ms,
        sum(memory_usage) AS memory_usage_bytes,
        max(memory_usage) AS peak_memory_usage_bytes,
        sum(read_rows) AS read_rows,
        sum(read_bytes) AS read_bytes,
        sum(written_rows) AS written_rows,
        sum(written_bytes) AS written_bytes,
        0 AS merge_count,
        0 AS parts_count,
        'RMV' AS metric_source
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 1 MINUTE
      AND type = 'QueryFinish'
      AND (query LIKE '%events_agg_rmv%' OR query LIKE '%events_rmv_batch%')
      AND query NOT LIKE '%system%'
      AND query NOT LIKE '%resource_metrics%'
    """
    try:
        client.command(query)
        return True
    except Exception as e:
        print(f"❌ RMV metrics collection failed: {e}")
        return False


def collect_merge_activity(client, session_id):
    """Merge 활동 수집"""
    query = f"""
    INSERT INTO {DATABASE}.merge_activity
    SELECT
        now64(3) AS collected_at,
        '{session_id}' AS session_id,
        table AS table_name,
        event_type,
        duration_ms AS merge_duration_ms,
        read_rows AS rows_read,
        written_rows AS rows_written,
        read_bytes AS bytes_read,
        written_bytes AS bytes_written,
        peak_memory_usage AS memory_usage
    FROM system.part_log
    WHERE database = '{DATABASE}'
      AND event_time >= now() - INTERVAL 1 MINUTE
      AND event_type IN ('MergeParts', 'MergePartsStart')
    """
    try:
        client.command(query)
        return True
    except Exception as e:
        print(f"❌ Merge activity collection failed: {e}")
        return False


def get_current_stats(client):
    """현재 통계 조회"""
    try:
        # Source table 행 수
        result = client.query(f"SELECT count() FROM {DATABASE}.events_source")
        source_count = result.result_rows[0][0]

        # MV table 행 수
        result = client.query(f"SELECT count() FROM {DATABASE}.events_agg_mv")
        mv_count = result.result_rows[0][0]

        # RMV table 행 수
        result = client.query(f"SELECT count() FROM {DATABASE}.events_agg_rmv")
        rmv_count = result.result_rows[0][0]

        # RMV 상태
        result = client.query(f"""
            SELECT status, last_success_time, next_refresh_time
            FROM system.view_refreshes
            WHERE database = '{DATABASE}' AND view = 'events_rmv_batch'
        """)
        if result.result_rows:
            rmv_status, last_refresh, next_refresh = result.result_rows[0]
        else:
            rmv_status = "Unknown"
            last_refresh = None
            next_refresh = None

        return {
            'source_count': source_count,
            'mv_count': mv_count,
            'rmv_count': rmv_count,
            'rmv_status': rmv_status,
            'last_refresh': last_refresh,
            'next_refresh': next_refresh
        }
    except Exception as e:
        print(f"❌ Failed to get current stats: {e}")
        return None


def main():
    """메인 실행 함수"""
    if len(sys.argv) < 2:
        print("Usage: python3 monitoring_collector.py <session_id>")
        print("Example: python3 monitoring_collector.py 12345678-1234-1234-1234-123456789abc")
        sys.exit(1)

    session_id = sys.argv[1]

    print(f"=" * 80)
    print(f"MV vs RMV Test - Monitoring Collector")
    print(f"=" * 80)
    print(f"Host: {HOST}")
    print(f"Database: {DATABASE}")
    print(f"Session ID: {session_id}")
    print(f"Collection Interval: {COLLECTION_INTERVAL} seconds")
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

        # 세션 확인
        result = client.query(f"""
            SELECT test_type, description, start_time
            FROM {DATABASE}.test_sessions
            WHERE session_id = '{session_id}'
        """)
        if not result.result_rows:
            print(f"❌ Session {session_id} not found")
            sys.exit(1)

        test_type, description, start_time = result.result_rows[0]
        print(f"✅ Session found: {description}")
        print(f"   Test type: {test_type}")
        print(f"   Start time: {start_time}")
        print()

    except Exception as e:
        print(f"❌ Connection failed: {e}")
        sys.exit(1)

    # 모니터링 수집 시작
    print(f"🚀 Starting monitoring collection at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Press Ctrl+C to stop")
    print()

    collection_count = 0
    start_time = time.time()

    try:
        while True:
            collection_start = time.time()
            collection_count += 1

            print(f"[{datetime.now().strftime('%H:%M:%S')}] Collection #{collection_count}")

            # 메트릭 수집
            success_count = 0

            if collect_parts_history(client, session_id):
                success_count += 1
                print(f"  ✅ Parts history collected")

            if collect_query_metrics_mv(client, session_id):
                success_count += 1
                print(f"  ✅ MV metrics collected")

            if collect_query_metrics_rmv(client, session_id):
                success_count += 1
                print(f"  ✅ RMV metrics collected")

            if collect_merge_activity(client, session_id):
                success_count += 1
                print(f"  ✅ Merge activity collected")

            # 현재 통계 출력
            stats = get_current_stats(client)
            if stats:
                print(f"  📊 Source: {stats['source_count']:,} rows | "
                      f"MV: {stats['mv_count']:,} rows | "
                      f"RMV: {stats['rmv_count']:,} rows")
                print(f"  📊 RMV Status: {stats['rmv_status']} | "
                      f"Next refresh: {stats['next_refresh']}")

            print(f"  ✅ {success_count}/4 collections successful")
            print()

            # 다음 수집까지 대기
            collection_duration = time.time() - collection_start
            sleep_time = max(0, COLLECTION_INTERVAL - collection_duration)
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print()
        print(f"⚠️  Interrupted by user")

    finally:
        total_duration = time.time() - start_time
        print()
        print(f"=" * 80)
        print(f"📊 Monitoring Summary")
        print(f"=" * 80)
        print(f"Total collections: {collection_count}")
        print(f"Total duration: {total_duration:.1f} seconds ({total_duration/60:.1f} minutes)")
        print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"=" * 80)

        client.close()
        print(f"✅ Connection closed")


if __name__ == '__main__':
    main()
