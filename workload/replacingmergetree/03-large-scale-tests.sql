-- ============================================
-- ReplacingMergeTree Lab - Large Scale Tests
-- 3. 대량 데이터 실험
-- ============================================

-- 테이블 초기화
TRUNCATE TABLE blog_test.user_events_large;

-- 배치 1: 100,000건의 초기 데이터 (user_id 0~99,999)
INSERT INTO blog_test.user_events_large (user_id, event_type, event_value, updated_at, insert_batch)
SELECT
    number % 100000 as user_id,
    'login' as event_type,
    rand() % 1000 as event_value,
    now() - INTERVAL (rand() % 86400) SECOND as updated_at,
    1 as insert_batch
FROM numbers(1000000);

-- 배치 1 삽입 직후 파트 상태
SELECT
    count(*) as part_count,
    sum(rows) as total_rows,
    min(modification_time) as oldest_part,
    max(modification_time) as newest_part
FROM system.parts
WHERE database = 'blog_test'
    AND table = 'user_events_large'
    AND active = 1;

-- 배치 2: 동일 user_id에 대한 업데이트 (50,000건)
INSERT INTO blog_test.user_events_large (user_id, event_type, event_value, updated_at, insert_batch)
SELECT
    number % 50000 as user_id,
    'login' as event_type,
    rand() % 1000 + 1000 as event_value,
    now() as updated_at,
    2 as insert_batch
FROM numbers(500000);

-- 배치 3: 또 다른 업데이트 (10,000건)
INSERT INTO blog_test.user_events_large (user_id, event_type, event_value, updated_at, insert_batch)
SELECT
    number % 10000 as user_id,
    'login' as event_type,
    9999 as event_value,
    now() as updated_at,
    3 as insert_batch
FROM numbers(100000);

-- 현재 파트 상태 확인
SELECT
    name,
    rows,
    formatReadableSize(bytes_on_disk) as size,
    modification_time
FROM system.parts
WHERE database = 'blog_test'
    AND table = 'user_events_large'
    AND active = 1
ORDER BY modification_time;

-- 배치별 데이터 분포 확인
SELECT
    insert_batch,
    count(*) as row_count,
    count(DISTINCT user_id) as unique_users,
    min(event_value) as min_value,
    max(event_value) as max_value,
    avg(event_value) as avg_value
FROM blog_test.user_events_large
GROUP BY insert_batch
ORDER BY insert_batch;
