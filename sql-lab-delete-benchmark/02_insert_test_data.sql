-- ============================================================================
-- ClickHouse DELETE Mechanism Benchmark - Insert Test Data
-- ClickHouse DELETE 메커니즘 벤치마크 - 테스트 데이터 생성
-- ============================================================================
-- Created: 2025-12-01
-- 작성일: 2025-12-01
-- Purpose: Generate 1,000,000 rows of test data
-- 목적: 1,000,000 rows의 테스트 데이터 생성
-- ============================================================================

-- ============================================================================
-- 1. ALTER DELETE Table Data Generation
-- 1. ALTER DELETE 테이블 데이터 생성
-- ============================================================================
-- Generate 1,000,000 event records (1 year span)
-- 1,000,000개의 이벤트 데이터 생성 (1년간)
-- ============================================================================

SELECT 'Inserting data into alter_delete_table...' as status;
SELECT 'alter_delete_table에 데이터 삽입 중...' as status_kr;

INSERT INTO delete_test.alter_delete_table
SELECT 
    number AS user_id,                                                          -- Sequential user ID / 순차 사용자 ID
    now() - INTERVAL number % 365 DAY AS event_time,                          -- Events distributed over 1 year / 1년간 분산된 이벤트
    ['signup', 'login', 'purchase', 'view', 'click'][number % 5 + 1] AS event_type,  -- 5 event types / 5가지 이벤트 타입
    rand() % 100 / 10.0 AS value,                                             -- Random value 0.0-9.9 / 랜덤 값 0.0-9.9
    ['active', 'pending', 'completed', 'cancelled'][number % 4 + 1] AS status -- 4 status types / 4가지 상태
FROM numbers(1000000);  -- Generate 1 million rows / 100만 개 row 생성

-- Verify insertion / 삽입 확인
SELECT 
    'alter_delete_table' as table_name,
    count() as total_rows,
    count(DISTINCT user_id) as unique_users,
    min(event_time) as earliest_event,
    max(event_time) as latest_event
FROM delete_test.alter_delete_table;

-- ============================================================================
-- 2. ReplacingMergeTree Table Data Generation
-- 2. ReplacingMergeTree 테이블 데이터 생성
-- ============================================================================
-- Same 1,000,000 records + version column
-- 동일한 1,000,000개 데이터 + version 컬럼
-- ============================================================================

SELECT 'Inserting data into replacing_merge_table...' as status;
SELECT 'replacing_merge_table에 데이터 삽입 중...' as status_kr;

INSERT INTO delete_test.replacing_merge_table
SELECT 
    number AS user_id,                                                          -- Sequential user ID / 순차 사용자 ID
    now() - INTERVAL number % 365 DAY AS event_time,                          -- Events distributed over 1 year / 1년간 분산된 이벤트
    ['signup', 'login', 'purchase', 'view', 'click'][number % 5 + 1] AS event_type,  -- 5 event types / 5가지 이벤트 타입
    rand() % 100 / 10.0 AS value,                                             -- Random value 0.0-9.9 / 랜덤 값 0.0-9.9
    ['active', 'pending', 'completed', 'cancelled'][number % 4 + 1] AS status, -- 4 status types / 4가지 상태
    1 AS version,                                                              -- Initial version / 초기 버전
    0 AS is_deleted                                                            -- Active state / 활성 상태
FROM numbers(1000000);  -- Generate 1 million rows / 100만 개 row 생성

-- Verify insertion / 삽입 확인
SELECT 
    'replacing_merge_table' as table_name,
    count() as total_rows,
    count(DISTINCT user_id) as unique_users,
    countIf(is_deleted = 0) as active_rows,
    countIf(is_deleted = 1) as deleted_rows,
    min(event_time) as earliest_event,
    max(event_time) as latest_event
FROM delete_test.replacing_merge_table;

-- ============================================================================
-- 3. CollapsingMergeTree Table Data Generation
-- 3. CollapsingMergeTree 테이블 데이터 생성
-- ============================================================================
-- Same 1,000,000 records + sign column (all starting with sign=1)
-- 동일한 1,000,000개 데이터 + sign 컬럼 (모두 1로 시작)
-- ============================================================================

SELECT 'Inserting data into collapsing_merge_table...' as status;
SELECT 'collapsing_merge_table에 데이터 삽입 중...' as status_kr;

INSERT INTO delete_test.collapsing_merge_table
SELECT 
    number AS user_id,                                                          -- Sequential user ID / 순차 사용자 ID
    now() - INTERVAL number % 365 DAY AS event_time,                          -- Events distributed over 1 year / 1년간 분산된 이벤트
    ['signup', 'login', 'purchase', 'view', 'click'][number % 5 + 1] AS event_type,  -- 5 event types / 5가지 이벤트 타입
    rand() % 100 / 10.0 AS value,                                             -- Random value 0.0-9.9 / 랜덤 값 0.0-9.9
    ['active', 'pending', 'completed', 'cancelled'][number % 4 + 1] AS status, -- 4 status types / 4가지 상태
    1 AS sign                                                                  -- Initial insert / 초기 추가
FROM numbers(1000000);  -- Generate 1 million rows / 100만 개 row 생성

-- Verify insertion / 삽입 확인
SELECT 
    'collapsing_merge_table' as table_name,
    count() as total_rows,
    count(DISTINCT user_id) as unique_users,
    countIf(sign = 1) as positive_rows,
    countIf(sign = -1) as negative_rows,
    sum(sign) as net_rows,
    min(event_time) as earliest_event,
    max(event_time) as latest_event
FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- Overall table status verification
-- 전체 테이블 상태 확인
-- ============================================================================

SELECT 'Overall Status / 전체 상태' as section;

SELECT 
    table,
    sum(rows) as total_rows,
    count() as parts_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) as compression_ratio
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table
ORDER BY table;

-- ============================================================================
-- Completion message
-- 완료 메시지
-- ============================================================================
SELECT 'Test data inserted successfully! 1,000,000 rows per table.' as status;
SELECT '테스트 데이터 삽입 완료! 테이블당 1,000,000 rows.' as status_kr;
