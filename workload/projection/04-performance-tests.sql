-- ============================================
-- ClickHouse Projection Lab - Performance Tests
-- 4. 성능 테스트 쿼리 및 실행 계획 분석
-- ============================================

-- Test 1: Projection 활성화 (자동 최적화)
SELECT
    category,
    country,
    sum(revenue) as total_revenue,
    sum(quantity) as total_quantity,
    count() as events
FROM projection_test.sales_events
WHERE toYYYYMM(event_time) = 202401
GROUP BY category, country
ORDER BY total_revenue DESC
LIMIT 10
SETTINGS allow_experimental_projection_optimization = 1;


-- Test 2: Projection 비활성화 (원본 테이블만 사용)
SELECT
    category,
    country,
    sum(revenue) as total_revenue,
    sum(quantity) as total_quantity,
    count() as events
FROM projection_test.sales_events
WHERE toYYYYMM(event_time) = 202401
GROUP BY category, country
ORDER BY total_revenue DESC
LIMIT 10
SETTINGS allow_experimental_projection_optimization = 0;


-- Test 3: Materialized View 사용
SELECT
    category,
    country,
    sum(total_revenue) as total_revenue,
    sum(total_quantity) as total_quantity,
    sum(event_count) as events
FROM projection_test.category_analysis_mv
WHERE month = 202401
GROUP BY category, country
ORDER BY total_revenue DESC
LIMIT 10;


-- Test 4: 브랜드 분석 (Projection 활용)
SELECT
    brand,
    customer_segment,
    sum(revenue) as total_revenue,
    count(DISTINCT user_id) as unique_users
FROM projection_test.sales_events
WHERE toDate(event_time) BETWEEN '2024-01-01' AND '2024-01-31'
GROUP BY brand, customer_segment
ORDER BY total_revenue DESC
LIMIT 10
SETTINGS allow_experimental_projection_optimization = 1;


-- Test 5: 복잡한 다차원 분석
SELECT
    category,
    country,
    customer_segment,
    toYYYYMM(event_time) as month,
    sum(revenue) as total_revenue,
    avg(price) as avg_price,
    count(DISTINCT user_id) as unique_users
FROM projection_test.sales_events
WHERE event_time >= '2024-01-01' AND event_time < '2024-04-01'
GROUP BY category, country, customer_segment, month
ORDER BY total_revenue DESC
LIMIT 20;


-- Test 6: 시계열 집계 테스트
SELECT
    toStartOfHour(event_time) as hour,
    category,
    sum(revenue) as hourly_revenue,
    count() as event_count
FROM projection_test.sales_events
WHERE event_time >= '2024-01-01' AND event_time < '2024-01-02'
GROUP BY hour, category
ORDER BY hour, hourly_revenue DESC;


-- Test 7: 고객 세그먼트 분석
SELECT
    customer_segment,
    country,
    count(DISTINCT user_id) as unique_customers,
    sum(revenue) as total_revenue,
    avg(revenue) as avg_order_value
FROM projection_test.sales_events
WHERE toYYYYMM(event_time) = 202401
GROUP BY customer_segment, country
ORDER BY total_revenue DESC;


-- Test 8: 디바이스별 분석
SELECT
    device_type,
    payment_method,
    sum(revenue) as total_revenue,
    avg(session_duration) as avg_session,
    count() as transaction_count
FROM projection_test.sales_events
WHERE event_time >= '2024-01-01' AND event_time < '2024-02-01'
GROUP BY device_type, payment_method
ORDER BY total_revenue DESC;


-- ============================================
-- 실행 계획 분석
-- ============================================

-- Projection 사용 시 실행 계획
EXPLAIN indexes = 1, description = 1
SELECT
    category,
    country,
    sum(revenue) as total_revenue
FROM projection_test.sales_events
WHERE toYYYYMM(event_time) = 202401
GROUP BY category, country
SETTINGS allow_experimental_projection_optimization = 1;


-- Projection 미사용 시 실행 계획
EXPLAIN indexes = 1, description = 1
SELECT
    category,
    country,
    sum(revenue) as total_revenue
FROM projection_test.sales_events
WHERE toYYYYMM(event_time) = 202401
GROUP BY category, country
SETTINGS allow_experimental_projection_optimization = 0;
