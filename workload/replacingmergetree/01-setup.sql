-- ============================================
-- ReplacingMergeTree Lab - Setup
-- 1. 테스트 환경 준비 및 초기 테이블 생성
-- ============================================

-- 테스트용 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS blog_test;

-- 기본 테스트용 테이블 생성
CREATE TABLE IF NOT EXISTS blog_test.user_events_replacing
(
    user_id UInt64,
    event_type String,
    event_value Int64,
    updated_at DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (user_id, event_type);

-- 대량 테스트용 테이블 생성
CREATE TABLE IF NOT EXISTS blog_test.user_events_large
(
    user_id UInt64,
    event_type String,
    event_value Int64,
    updated_at DateTime DEFAULT now(),
    insert_batch UInt32
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (user_id, event_type);

-- 테이블 생성 확인
SELECT
    database,
    name,
    engine,
    create_table_query
FROM system.tables
WHERE database = 'blog_test'
FORMAT Vertical;
