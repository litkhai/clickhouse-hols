-- ============================================
-- ReplacingMergeTree Lab - Optimization
-- 6. OPTIMIZE TABLE FINAL 효과 검증 및 argMax 대안
-- ============================================

-- ============================================================
-- PART 1: OPTIMIZE TABLE FINAL 검증
-- ============================================================

-- OPTIMIZE 실행 전 상태 확인
SELECT
    'BEFORE OPTIMIZE' as state,
    count(*) as part_count,
    sum(rows) as total_rows
FROM system.parts
WHERE database = 'blog_test'
    AND table = 'user_events_large'
    AND active = 1;

-- 기본 테이블 OPTIMIZE TABLE FINAL 실행
OPTIMIZE TABLE blog_test.user_events_replacing FINAL;

-- 대량 테이블 OPTIMIZE TABLE FINAL 실행
OPTIMIZE TABLE blog_test.user_events_large FINAL;

-- OPTIMIZE 실행 후 파트 상태
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

-- OPTIMIZE 후 중복 제거 확인
SELECT
    'AFTER OPTIMIZE (no FINAL)' as state,
    count(*) as row_count
FROM blog_test.user_events_large

UNION ALL

SELECT
    'AFTER OPTIMIZE (with FINAL)' as state,
    count(*) as row_count
FROM blog_test.user_events_large FINAL;

-- 특정 user_id 확인 (이제 단일 행)
SELECT user_id, event_value, updated_at, insert_batch, _part
FROM blog_test.user_events_large
WHERE user_id = 5;

-- ============================================================
-- PART 2: argMax 대안 패턴 테스트
-- ============================================================

-- argMax 패턴 (FINAL 없이 정확한 결과)
SELECT
    user_id,
    argMax(event_value, updated_at) as latest_value,
    max(updated_at) as latest_time
FROM blog_test.user_events_large
WHERE user_id < 5
GROUP BY user_id
ORDER BY user_id;

-- FINAL 결과와 비교
SELECT
    user_id,
    event_value,
    updated_at
FROM blog_test.user_events_large FINAL
WHERE user_id < 5
ORDER BY user_id;

-- 전체 집계에 argMax 사용
SELECT
    count(*) as cnt,
    sum(latest_value) as total
FROM (
    SELECT
        user_id,
        event_type,
        argMax(event_value, updated_at) as latest_value
    FROM blog_test.user_events_large
    GROUP BY user_id, event_type
);

-- argMax vs FINAL 성능 비교용 쿼리
-- (query_log에서 확인 가능)
SELECT
    user_id,
    argMax(event_value, updated_at) as latest_value,
    max(updated_at) as latest_time,
    count(*) as version_count
FROM blog_test.user_events_large
WHERE user_id < 1000
GROUP BY user_id
ORDER BY user_id
SETTINGS max_threads = 1;
