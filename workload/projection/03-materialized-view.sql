-- ============================================
-- ClickHouse Projection Lab - Materialized View
-- 3. Materialized View 생성 (Projection과 비교용)
-- ============================================

-- Target 테이블 생성
CREATE TABLE IF NOT EXISTS projection_test.category_analysis_mv
(
    category String,
    country String,
    month UInt32,
    total_revenue Decimal(20, 2),
    total_quantity UInt64,
    event_count UInt64,
    avg_price Float64
)
ENGINE = SummingMergeTree()
ORDER BY (category, country, month);

-- Materialized View 생성
CREATE MATERIALIZED VIEW IF NOT EXISTS projection_test.category_analysis_mv_source
TO projection_test.category_analysis_mv
AS
SELECT
    category,
    country,
    toYYYYMM(event_time) as month,
    sum(revenue) as total_revenue,
    sum(quantity) as total_quantity,
    count() as event_count,
    avg(price) as avg_price
FROM projection_test.sales_events
GROUP BY category, country, month;

-- 기존 데이터 적재
INSERT INTO projection_test.category_analysis_mv
SELECT
    category,
    country,
    toYYYYMM(event_time) as month,
    sum(revenue) as total_revenue,
    sum(quantity) as total_quantity,
    count() as event_count,
    avg(price) as avg_price
FROM projection_test.sales_events
GROUP BY category, country, month;

-- 데이터 확인
SELECT
    count() as total_rows,
    sum(total_revenue) as total_revenue,
    sum(event_count) as total_events
FROM projection_test.category_analysis_mv;
