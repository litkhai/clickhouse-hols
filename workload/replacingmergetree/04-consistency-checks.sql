-- ============================================
-- ReplacingMergeTree Lab - Consistency Checks
-- 4. 정합성 불일치 검증
-- ============================================

-- FINAL 없이 특정 user_id의 중복 확인
SELECT
    count(*) as row_count,
    count(DISTINCT insert_batch) as batch_count
FROM blog_test.user_events_large
WHERE user_id = 5;

-- FINAL과 함께 특정 user_id 조회
SELECT *
FROM blog_test.user_events_large FINAL
WHERE user_id = 5;

-- 전체 행 수 비교: FINAL 유무
SELECT
    'WITHOUT FINAL' as query_type,
    count(*) as row_count
FROM blog_test.user_events_large

UNION ALL

SELECT
    'WITH FINAL' as query_type,
    count(*) as row_count
FROM blog_test.user_events_large FINAL;

-- 집계 결과 비교: FINAL 없이 (잘못된 결과)
SELECT
    'WITHOUT FINAL' as query_type,
    count(*) as total_users,
    sum(event_value) as total_value,
    avg(event_value) as avg_value
FROM blog_test.user_events_large;

-- 집계 결과 비교: FINAL과 함께 (정확한 결과)
SELECT
    'WITH FINAL' as query_type,
    count(*) as total_users,
    sum(event_value) as total_value,
    avg(event_value) as avg_value
FROM blog_test.user_events_large FINAL;

-- 특정 user_id의 모든 중복 행 확인
SELECT
    user_id,
    event_value,
    updated_at,
    insert_batch,
    _part
FROM blog_test.user_events_large
WHERE user_id = 5
ORDER BY updated_at;

-- 중복도가 높은 user_id 찾기 (샘플링)
SELECT
    user_id,
    count(*) as duplicate_count,
    count(DISTINCT insert_batch) as batch_count,
    groupArray(event_value) as values
FROM blog_test.user_events_large
WHERE user_id < 100
GROUP BY user_id
HAVING duplicate_count > 1
ORDER BY duplicate_count DESC
LIMIT 10;
