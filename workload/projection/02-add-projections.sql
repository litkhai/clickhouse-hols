-- ============================================
-- ClickHouse Projection Lab - Add Projections
-- 2. Projection 생성 및 구체화
-- ============================================

-- Projection 1: 카테고리별 분석
ALTER TABLE projection_test.sales_events
ADD PROJECTION category_analysis
(
    SELECT
        category,
        country,
        toYYYYMM(event_time) as month,
        sum(revenue) as total_revenue,
        sum(quantity) as total_quantity,
        count() as event_count,
        avg(price) as avg_price
    GROUP BY category, country, month
);

-- Projection 구체화 (비동기)
ALTER TABLE projection_test.sales_events
MATERIALIZE PROJECTION category_analysis;

-- 동기 구체화 (테스트 시 사용)
-- ALTER TABLE projection_test.sales_events
-- MATERIALIZE PROJECTION category_analysis
-- SETTINGS mutations_sync = 1;


-- Projection 2: 브랜드별 일별 통계
ALTER TABLE projection_test.sales_events
ADD PROJECTION brand_daily_stats
(
    SELECT
        brand,
        toDate(event_time) as date,
        customer_segment,
        sum(revenue) as daily_revenue,
        count(DISTINCT user_id) as unique_users,
        avg(session_duration) as avg_session
    GROUP BY brand, date, customer_segment
);

-- Projection 구체화
ALTER TABLE projection_test.sales_events
MATERIALIZE PROJECTION brand_daily_stats;

-- 동기 구체화 (테스트 시 사용)
-- ALTER TABLE projection_test.sales_events
-- MATERIALIZE PROJECTION brand_daily_stats
-- SETTINGS mutations_sync = 1;


-- Projection 목록 확인
SELECT
    database,
    table,
    name as projection_name,
    type,
    sorting_key,
    query
FROM system.projections
WHERE database = 'projection_test';


-- Projection 크기 확인
SELECT
    parent_name,
    name as projection_name,
    formatReadableSize(sum(bytes_on_disk)) as projection_size,
    sum(rows) as projection_rows,
    count() as parts_count
FROM system.projection_parts
WHERE database = 'projection_test' AND active = 1
GROUP BY parent_name, name
ORDER BY sum(bytes_on_disk) DESC;


-- Projection 관리 명령어 (참고용)
-- ============================================

-- Projection 삭제
-- ALTER TABLE projection_test.sales_events
-- DROP PROJECTION category_analysis;

-- ALTER TABLE projection_test.sales_events
-- DROP PROJECTION brand_daily_stats;

-- 테이블 최적화 (Projection도 함께 최적화됨)
-- OPTIMIZE TABLE projection_test.sales_events FINAL;