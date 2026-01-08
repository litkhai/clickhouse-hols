-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 2. Projection 생성 및 Custom Settings 적용
-- ============================================

-- ----------------------------------------------------------------------------
-- 현재 버전 제약 사항 (25.10)
-- ----------------------------------------------------------------------------
-- ❌ WITH SETTINGS 문법이 아직 지원되지 않음
-- ✅ 25.12+ 버전부터 사용 가능

-- ❌ 시도 1: 괄호로 감싼 SETTINGS (25.10에서 실패)
-- ALTER TABLE projection_granularity_test.events
-- ADD PROJECTION user_lookup_g256 (
--     SELECT * ORDER BY user_id, event_time
-- )
-- WITH SETTINGS (
--     index_granularity = 256
-- );
-- Error: Syntax error at position 187 (WITH)


-- ❌ 시도 2: 괄호 없이 SETTINGS (25.10에서 실패)
-- ALTER TABLE projection_granularity_test.events
-- ADD PROJECTION user_lookup_g256 (
--     SELECT * ORDER BY user_id, event_time
-- )
-- WITH SETTINGS index_granularity = 256;
-- Error: Syntax error at position 187 (WITH)


-- ✅ 기본 Projection 생성 (원본 granularity 상속)
ALTER TABLE projection_granularity_test.events
ADD PROJECTION user_lookup (
    SELECT * ORDER BY user_id, event_time
);

-- Projection 구체화 (동기 모드)
ALTER TABLE projection_granularity_test.events
MATERIALIZE PROJECTION user_lookup
SETTINGS mutations_sync = 2;


-- ----------------------------------------------------------------------------
-- 25.12+ 버전에서 사용 가능한 문법
-- ----------------------------------------------------------------------------

-- 다중 Projection 전략 (버전 업그레이드 후 사용)
-- Projection 1: User lookup (Point Query 최적화)
-- ALTER TABLE projection_granularity_test.events
-- ADD PROJECTION user_lookup_optimized (
--     SELECT * ORDER BY user_id, event_time
-- ) WITH SETTINGS (
--     index_granularity = 256
-- );

-- Projection 2: Session analysis (Medium range 쿼리)
-- ALTER TABLE projection_granularity_test.events
-- ADD PROJECTION session_analysis (
--     SELECT * ORDER BY session_id, event_time
-- ) WITH SETTINGS (
--     index_granularity = 512
-- );

-- Projection 3: Event type aggregation
-- ALTER TABLE projection_granularity_test.events
-- ADD PROJECTION event_stats (
--     SELECT
--         toDate(event_time) as date,
--         event_type,
--         count() as event_count,
--         sum(revenue) as total_revenue,
--         uniq(user_id) as unique_users
--     GROUP BY date, event_type
-- ) WITH SETTINGS (
--     index_granularity = 2048
-- );


-- ----------------------------------------------------------------------------
-- Projection 목록 확인
-- ----------------------------------------------------------------------------

SELECT
    database,
    table,
    name as projection_name,
    type,
    sorting_key,
    query
FROM system.projections
WHERE database = 'projection_granularity_test'
ORDER BY table, name;


-- Projection Parts 분석
SELECT
    database,
    table,
    name as projection_name,
    sum(rows) as total_rows,
    sum(marks) as total_marks,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    count() as part_count
FROM system.projection_parts
WHERE database = 'projection_granularity_test'
  AND active = 1
GROUP BY database, table, name
ORDER BY table, name;


-- Mutation 진행 상황 확인
SELECT
    database,
    table,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_fail_reason
FROM system.mutations
WHERE database = 'projection_granularity_test'
ORDER BY create_time DESC
LIMIT 10;
