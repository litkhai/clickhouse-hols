-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 1. 테스트 환경 준비 및 데이터 생성
-- ============================================

-- 테스트 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS projection_granularity_test;

-- 베이스 테이블 생성 (기본 granularity = 8192)
CREATE TABLE projection_granularity_test.events (
    event_time DateTime,
    user_id UInt32,
    session_id String,
    event_type LowCardinality(String),
    page_url String,
    revenue Decimal(10,2)
) ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
ORDER BY event_time
SETTINGS index_granularity = 8192;

-- 샘플 데이터 삽입 (100만 행)
INSERT INTO projection_granularity_test.events
SELECT
    now() - INTERVAL rand() % 86400 SECOND as event_time,
    rand() % 100000 as user_id,
    concat('session_', toString(rand() % 50000)) as session_id,
    ['click', 'view', 'purchase', 'add_cart', 'search'][rand() % 5 + 1] as event_type,
    concat('/page/', toString(rand() % 1000)) as page_url,
    round(rand() % 10000 / 100, 2) as revenue
FROM numbers(1000000);

-- 데이터 확인
SELECT
    count() as total_rows,
    min(event_time) as min_time,
    max(event_time) as max_time,
    count(DISTINCT user_id) as unique_users,
    sum(revenue) as total_revenue
FROM projection_granularity_test.events;
