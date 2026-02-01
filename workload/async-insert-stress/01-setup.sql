-- ============================================================
-- ClickHouse Async Insert 스트레스 테스트 - 환경 설정
-- ============================================================

-- 테스트 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS async_insert_test;

-- 메인 테스트 테이블
CREATE TABLE IF NOT EXISTS async_insert_test.test_logs
(
    id UInt64,
    event_time DateTime64(3) DEFAULT now64(3),
    user_id UInt32,
    event_type String,
    payload String,
    test_case String,
    insert_timestamp DateTime64(3) DEFAULT now64(3)
)
ENGINE = MergeTree()
ORDER BY (event_time, id);

-- 테스트 결과 저장 테이블
CREATE TABLE IF NOT EXISTS async_insert_test.test_results
(
    test_case String,
    test_time DateTime DEFAULT now(),
    async_insert UInt8,
    wait_for_async_insert UInt8,
    busy_timeout_ms UInt32,
    expected_rows UInt64,
    actual_rows UInt64,
    success_rate Float64,
    avg_insert_time_ms Float64,
    notes String
)
ENGINE = MergeTree()
ORDER BY (test_case, test_time);

-- 테이블 초기화
TRUNCATE TABLE async_insert_test.test_logs;
