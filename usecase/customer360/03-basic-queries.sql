-- ============================================================================
-- Customer 360 Lab Step 3: Basic Analysis Queries
-- Customer 360 실습 Step 3: 기본 분석 쿼리
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Basic analytics queries for Customer 360 insights
-- 목적: Customer 360 인사이트를 위한 기본 분석 쿼리
-- ============================================================================

-- ============================================================================
-- 3.1 Customer 360 Unified View (5-way JOIN)
-- 3.1 Customer 360 통합 뷰 (5-way JOIN)
-- ============================================================================
-- View all customer activities in one place
-- 개별 고객의 모든 활동을 한눈에 보기
-- ============================================================================

SELECT
    c.customer_id,
    c.email,
    concat(c.first_name, ' ', c.last_name) AS full_name,
    c.customer_segment,
    c.lifetime_value,

    -- 거래 통계
    count(DISTINCT t.transaction_id) AS total_transactions,
    sum(t.total_amount) AS total_spent,
    avg(t.total_amount) AS avg_transaction_value,
    max(t.transaction_date) AS last_purchase_date,
    dateDiff('day', max(t.transaction_date), now()) AS days_since_last_purchase,

    -- 이벤트 통계
    count(DISTINCT e.event_id) AS total_events,
    count(DISTINCT e.session_id) AS total_sessions,

    -- 서포트 통계
    count(DISTINCT s.ticket_id) AS total_tickets,
    avg(s.satisfaction_score) AS avg_satisfaction,

    -- 캠페인 반응
    countIf(cr.opened_at IS NOT NULL) AS campaigns_opened,
    countIf(cr.clicked_at IS NOT NULL) AS campaigns_clicked,
    countIf(cr.converted_at IS NOT NULL) AS campaigns_converted,

    -- 리뷰 활동
    count(DISTINCT pr.review_id) AS total_reviews,
    avg(pr.rating) AS avg_rating_given

FROM customer360.customers c
LEFT JOIN customer360.transactions t ON c.customer_id = t.customer_id
LEFT JOIN customer360.customer_events e ON c.customer_id = e.customer_id
LEFT JOIN customer360.support_tickets s ON c.customer_id = s.customer_id
LEFT JOIN customer360.campaign_responses cr ON c.customer_id = cr.customer_id
LEFT JOIN customer360.product_reviews pr ON c.customer_id = pr.customer_id

WHERE c.customer_id IN (SELECT customer_id FROM customer360.customers LIMIT 10)
GROUP BY c.customer_id, c.email, full_name, c.customer_segment, c.lifetime_value
ORDER BY total_spent DESC;

-- ============================================================================
-- 3.2 Channel Analysis
-- 3.2 채널별 고객 행동 분석
-- ============================================================================
-- Analyze revenue and customer behavior by channel (last 30 days)
-- 최근 30일간 채널별 매출 및 고객 분석
-- ============================================================================

SELECT
    channel,
    count(DISTINCT customer_id) AS unique_customers,
    count() AS total_transactions,
    sum(total_amount) AS total_revenue,
    avg(total_amount) AS avg_transaction_value,
    round(sum(total_amount) * 100.0 / sum(sum(total_amount)) OVER (), 2) AS revenue_share_pct
FROM customer360.transactions
WHERE transaction_type = 'purchase'
  AND transaction_date >= now() - INTERVAL 30 DAY
GROUP BY channel
ORDER BY total_revenue DESC;

-- ============================================================================
-- 3.3 Product Preferences by Segment
-- 3.3 세그먼트별 제품 선호도 분석
-- ============================================================================
-- Analyze product category preferences by customer segment
-- 고객 세그먼트별로 어떤 제품 카테고리를 선호하는지 분석
-- ============================================================================

SELECT
    c.customer_segment,
    t.product_category,
    count(DISTINCT t.customer_id) AS unique_customers,
    count() AS purchase_count,
    sum(t.total_amount) AS total_revenue,
    round(avg(t.total_amount), 2) AS avg_transaction_value,

    -- 해당 세그먼트 내 카테고리 점유율
    round(count() * 100.0 / sum(count()) OVER (PARTITION BY c.customer_segment), 2) AS segment_category_share
FROM customer360.customers c
JOIN customer360.transactions t ON c.customer_id = t.customer_id
WHERE t.transaction_type = 'purchase'
  AND t.transaction_date >= now() - INTERVAL 30 DAY
GROUP BY c.customer_segment, t.product_category
ORDER BY c.customer_segment, total_revenue DESC
LIMIT 40;

-- ============================================================================
-- 3.4 Monthly Business Trends (6 months)
-- 3.4 월별 비즈니스 트렌드 분석 (6개월)
-- ============================================================================
-- Track business growth trends over time
-- 시계열로 비즈니스 성장 추이 파악
-- ============================================================================

SELECT
    toStartOfMonth(transaction_date) AS month,
    count(DISTINCT customer_id) AS active_customers,
    count() AS total_transactions,
    sum(total_amount) AS total_revenue,
    round(avg(total_amount), 2) AS avg_order_value,
    countIf(is_first_purchase) AS first_time_buyers,

    -- 전월 대비 성장률
    round((count() - lagInFrame(count()) OVER (ORDER BY month)) * 100.0 /
          nullIf(lagInFrame(count()) OVER (ORDER BY month), 0), 2) AS transaction_growth_pct,
    round((sum(total_amount) - lagInFrame(sum(total_amount)) OVER (ORDER BY month)) * 100.0 /
          nullIf(lagInFrame(sum(total_amount)) OVER (ORDER BY month), 0), 2) AS revenue_growth_pct
FROM customer360.transactions
WHERE transaction_type = 'purchase'
  AND transaction_date >= now() - INTERVAL 180 DAY
GROUP BY month
ORDER BY month;

-- ============================================================================
-- 3.5 Channel Growth Trends (6 months)
-- 3.5 채널별 성장 추이 (6개월)
-- ============================================================================
-- Monthly performance by channel
-- 각 채널의 월별 성과 추이
-- ============================================================================

SELECT
    toStartOfMonth(transaction_date) AS month,
    channel,
    count(DISTINCT customer_id) AS unique_customers,
    count() AS transactions,
    sum(total_amount) AS revenue,
    round(avg(total_amount), 2) AS avg_order_value,

    -- 채널별 점유율
    round(sum(total_amount) * 100.0 / sum(sum(total_amount)) OVER (PARTITION BY toStartOfMonth(transaction_date)), 2) AS revenue_share_pct
FROM customer360.transactions
WHERE transaction_type = 'purchase'
  AND transaction_date >= now() - INTERVAL 180 DAY
GROUP BY month, channel
ORDER BY month, revenue DESC;

-- ============================================================================
-- 3.6 Conversion Funnel Analysis
-- 3.6 고객별 전환 퍼널 분석
-- ============================================================================
-- Analyze conversion rates from visit to purchase
-- 웹사이트 방문부터 구매까지의 전환율 분석
-- ============================================================================

WITH funnel_events AS (
    SELECT
        customer_id,
        countIf(event_type = 'page_view') AS page_views,
        countIf(event_type = 'product_view') AS product_views,
        countIf(event_type = 'add_to_cart') AS cart_adds,
        countIf(event_type = 'checkout_start') AS checkout_starts,
        countIf(event_type = 'purchase_complete') AS purchases
    FROM customer360.customer_events
    WHERE event_timestamp >= now() - INTERVAL 7 DAY
    GROUP BY customer_id
)
SELECT
    'Total Customers' AS stage,
    count() AS customers,
    count() AS from_previous,
    100.0 AS conversion_rate,
    0.0 AS drop_off_rate
FROM funnel_events

UNION ALL

SELECT
    'Had Page Views' AS stage,
    countIf(page_views > 0) AS customers,
    count() AS from_previous,
    round(countIf(page_views > 0) * 100.0 / count(), 2) AS conversion_rate,
    round((count() - countIf(page_views > 0)) * 100.0 / count(), 2) AS drop_off_rate
FROM funnel_events

UNION ALL

SELECT
    'Viewed Products' AS stage,
    countIf(product_views > 0) AS customers,
    countIf(page_views > 0) AS from_previous,
    round(countIf(product_views > 0) * 100.0 / nullIf(countIf(page_views > 0), 0), 2) AS conversion_rate,
    round((countIf(page_views > 0) - countIf(product_views > 0)) * 100.0 / nullIf(countIf(page_views > 0), 0), 2) AS drop_off_rate
FROM funnel_events

UNION ALL

SELECT
    'Added to Cart' AS stage,
    countIf(cart_adds > 0) AS customers,
    countIf(product_views > 0) AS from_previous,
    round(countIf(cart_adds > 0) * 100.0 / nullIf(countIf(product_views > 0), 0), 2) AS conversion_rate,
    round((countIf(product_views > 0) - countIf(cart_adds > 0)) * 100.0 / nullIf(countIf(product_views > 0), 0), 2) AS drop_off_rate
FROM funnel_events

UNION ALL

SELECT
    'Started Checkout' AS stage,
    countIf(checkout_starts > 0) AS customers,
    countIf(cart_adds > 0) AS from_previous,
    round(countIf(checkout_starts > 0) * 100.0 / nullIf(countIf(cart_adds > 0), 0), 2) AS conversion_rate,
    round((countIf(cart_adds > 0) - countIf(checkout_starts > 0)) * 100.0 / nullIf(countIf(cart_adds > 0), 0), 2) AS drop_off_rate
FROM funnel_events

UNION ALL

SELECT
    'Completed Purchase' AS stage,
    countIf(purchases > 0) AS customers,
    countIf(checkout_starts > 0) AS from_previous,
    round(countIf(purchases > 0) * 100.0 / nullIf(countIf(checkout_starts > 0), 0), 2) AS conversion_rate,
    round((countIf(checkout_starts > 0) - countIf(purchases > 0)) * 100.0 / nullIf(countIf(checkout_starts > 0), 0), 2) AS drop_off_rate
FROM funnel_events;
