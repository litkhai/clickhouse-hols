-- ============================================================================
-- Customer 360 Lab Step 4: Advanced Analysis Queries
-- Customer 360 실습 Step 4: 고급 분석 쿼리
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Advanced analytics queries for deep customer insights
-- 목적: 심화된 고객 인사이트를 위한 고급 분석 쿼리
-- ============================================================================

-- ============================================================================
-- 4.1 RFM (Recency, Frequency, Monetary) Analysis
-- 4.1 RFM (Recency, Frequency, Monetary) 분석
-- ============================================================================
-- Customer segmentation based on RFM criteria
-- 고객을 RFM 기준으로 세그먼트화
-- ============================================================================

WITH rfm_data AS (
    SELECT
        customer_id,
        dateDiff('day', max(transaction_date), now()) AS recency,
        count(DISTINCT transaction_id) AS frequency,
        sum(total_amount) AS monetary
    FROM customer360.transactions
    WHERE transaction_type = 'purchase'
    GROUP BY customer_id
),
rfm_scored AS (
    SELECT
        customer_id,
        recency,
        frequency,
        monetary,
        CASE
            WHEN recency <= 7 THEN 5
            WHEN recency <= 14 THEN 4
            WHEN recency <= 30 THEN 3
            WHEN recency <= 60 THEN 2
            ELSE 1
        END AS r_score,
        ntile(5) OVER (ORDER BY frequency) AS f_score,
        ntile(5) OVER (ORDER BY monetary) AS m_score
    FROM rfm_data
)
SELECT
    concat(toString(r_score), toString(f_score), toString(m_score)) AS rfm_segment,
    count() AS customer_count,
    avg(recency) AS avg_recency,
    avg(frequency) AS avg_frequency,
    avg(monetary) AS avg_monetary_value,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 4 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Regular'
    END AS customer_category
FROM rfm_scored
GROUP BY rfm_segment, customer_category
ORDER BY customer_count DESC
LIMIT 20;

-- ============================================================================
-- 4.2 Cohort Analysis (Retention by Registration Month) - 6 months
-- 4.2 코호트 분석 (등록 월별 리텐션) - 6개월 확장
-- ============================================================================
-- Calculate monthly retention rates by cohort
-- 각 코호트의 월별 리텐션율 계산
-- ============================================================================

WITH cohort_data AS (
    SELECT
        c.customer_id,
        toStartOfMonth(c.registration_date) AS cohort_month,
        toStartOfMonth(t.transaction_date) AS transaction_month,
        dateDiff('month', toStartOfMonth(c.registration_date), toStartOfMonth(t.transaction_date)) AS months_since_registration
    FROM customer360.customers c
    JOIN customer360.transactions t ON c.customer_id = t.customer_id
    WHERE transaction_type = 'purchase'
      AND t.transaction_date >= now() - INTERVAL 180 DAY
)
SELECT
    cohort_month,
    count(DISTINCT CASE WHEN months_since_registration = 0 THEN customer_id END) AS month_0,
    count(DISTINCT CASE WHEN months_since_registration = 1 THEN customer_id END) AS month_1,
    count(DISTINCT CASE WHEN months_since_registration = 2 THEN customer_id END) AS month_2,
    count(DISTINCT CASE WHEN months_since_registration = 3 THEN customer_id END) AS month_3,
    count(DISTINCT CASE WHEN months_since_registration = 4 THEN customer_id END) AS month_4,
    count(DISTINCT CASE WHEN months_since_registration = 5 THEN customer_id END) AS month_5,
    count(DISTINCT CASE WHEN months_since_registration = 6 THEN customer_id END) AS month_6,

    round(count(DISTINCT CASE WHEN months_since_registration = 1 THEN customer_id END) * 100.0 /
          nullIf(count(DISTINCT CASE WHEN months_since_registration = 0 THEN customer_id END), 0), 2) AS retention_month_1,
    round(count(DISTINCT CASE WHEN months_since_registration = 3 THEN customer_id END) * 100.0 /
          nullIf(count(DISTINCT CASE WHEN months_since_registration = 0 THEN customer_id END), 0), 2) AS retention_month_3,
    round(count(DISTINCT CASE WHEN months_since_registration = 6 THEN customer_id END) * 100.0 /
          nullIf(count(DISTINCT CASE WHEN months_since_registration = 0 THEN customer_id END), 0), 2) AS retention_month_6
FROM cohort_data
GROUP BY cohort_month
ORDER BY cohort_month DESC
LIMIT 7;

-- ============================================================================
-- 4.3 Customer Lifetime Value (CLV) Prediction Metrics
-- 4.3 고객 생애 가치 (CLV) 예측 지표
-- ============================================================================
-- Predict CLV using purchase frequency and average order value
-- 구매 빈도, 평균 주문 금액 등으로 CLV 예측
-- ============================================================================

WITH customer_metrics AS (
    SELECT
        customer_id,
        count(DISTINCT transaction_id) AS purchase_frequency,
        avg(total_amount) AS avg_order_value,
        dateDiff('day', min(transaction_date), max(transaction_date)) /
            nullIf(count(DISTINCT transaction_id) - 1, 0) AS avg_days_between_purchases,
        dateDiff('day', min(transaction_date), max(transaction_date)) AS customer_lifespan_days
    FROM customer360.transactions
    WHERE transaction_type = 'purchase'
    GROUP BY customer_id
    HAVING purchase_frequency > 1
)
SELECT
    quantile(0.25)(purchase_frequency) AS purchase_freq_q1,
    quantile(0.5)(purchase_frequency) AS purchase_freq_median,
    quantile(0.75)(purchase_frequency) AS purchase_freq_q3,

    round(quantile(0.25)(avg_order_value), 2) AS aov_q1,
    round(quantile(0.5)(avg_order_value), 2) AS aov_median,
    round(quantile(0.75)(avg_order_value), 2) AS aov_q3,

    round(quantile(0.25)(avg_days_between_purchases), 2) AS days_between_q1,
    round(quantile(0.5)(avg_days_between_purchases), 2) AS days_between_median,
    round(quantile(0.75)(avg_days_between_purchases), 2) AS days_between_q3,

    -- 간단한 CLV 예측 (purchase_frequency * avg_order_value)
    round(quantile(0.5)(purchase_frequency * avg_order_value), 2) AS estimated_clv_median
FROM customer_metrics;

-- ============================================================================
-- 4.4 Customer Lifetime Value Analysis (6-month LTV)
-- 4.4 고객 생애 가치 분석 (6개월 LTV)
-- ============================================================================
-- Classify customers by value segments
-- 고객을 가치 세그먼트별로 분류
-- ============================================================================

WITH customer_spend AS (
    SELECT
        customer_id,
        sum(total_amount) AS total_spent,
        count() AS purchase_count,
        min(transaction_date) AS first_purchase,
        max(transaction_date) AS last_purchase,
        dateDiff('day', min(transaction_date), max(transaction_date)) AS lifespan_days
    FROM customer360.transactions
    WHERE transaction_type = 'purchase'
      AND transaction_date >= now() - INTERVAL 180 DAY
      AND customer_id % 100 = 0  -- 1% 샘플링
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN total_spent < 1000 THEN 'Low Value'
        WHEN total_spent < 5000 THEN 'Medium Value'
        WHEN total_spent < 10000 THEN 'High Value'
        ELSE 'VIP'
    END AS value_segment,
    count() AS customer_count,
    round(avg(purchase_count), 2) AS avg_purchases,
    round(avg(total_spent), 2) AS avg_ltv_6months,
    round(avg(lifespan_days), 2) AS avg_lifespan_days,
    round(min(total_spent), 2) AS min_spend,
    round(max(total_spent), 2) AS max_spend
FROM customer_spend
GROUP BY value_segment
ORDER BY avg_ltv_6months DESC;

-- ============================================================================
-- 4.5 Churn Risk Identification (Churn Prediction)
-- 4.5 이탈 위험 고객 식별 (Churn Prediction)
-- ============================================================================
-- Identify at-risk customers by segment
-- 고객 세그먼트별 이탈 위험 고객 파악
-- ============================================================================

WITH last_activity AS (
    SELECT
        c.customer_id,
        c.customer_segment,
        c.lifetime_value,
        max(t.transaction_date) AS last_purchase_date,
        count(t.transaction_id) AS total_purchases,
        max(e.event_timestamp) AS last_event_date,
        max(s.created_at) AS last_ticket_date
    FROM customer360.customers c
    LEFT JOIN customer360.transactions t ON c.customer_id = t.customer_id
    LEFT JOIN customer360.customer_events e ON c.customer_id = e.customer_id
    LEFT JOIN customer360.support_tickets s ON c.customer_id = s.customer_id
    WHERE c.is_active = true
      AND c.customer_id % 10000 = 0  -- 샘플링
    GROUP BY c.customer_id, c.customer_segment, c.lifetime_value
)
SELECT
    customer_segment,
    count() AS total_customers,
    countIf(dateDiff('day', last_purchase_date, now()) > 30) AS inactive_30_days,
    countIf(dateDiff('day', last_purchase_date, now()) > 45) AS inactive_45_days,
    countIf(dateDiff('day', last_purchase_date, now()) > 60) AS inactive_60_days,

    round(countIf(dateDiff('day', last_purchase_date, now()) > 30) * 100.0 / count(), 2) AS churn_risk_pct,

    avg(lifetime_value) AS avg_lifetime_value,
    sum(CASE WHEN dateDiff('day', last_purchase_date, now()) > 45 THEN lifetime_value ELSE 0 END) AS at_risk_value
FROM last_activity
GROUP BY customer_segment
ORDER BY churn_risk_pct DESC;

-- ============================================================================
-- 4.6 Multi-touch Marketing Attribution
-- 4.6 멀티 터치 마케팅 어트리뷰션
-- ============================================================================
-- Analyze which campaigns led to purchases
-- 어떤 캠페인이 구매로 연결되었는지 분석
-- ============================================================================

WITH campaign_journey AS (
    SELECT
        cr.customer_id,
        t.transaction_id,
        t.total_amount,
        cr.campaign_id,
        cr.campaign_type,
        cr.sent_at,
        t.transaction_date,
        dateDiff('hour', cr.sent_at, t.transaction_date) AS hours_to_conversion,
        row_number() OVER (PARTITION BY cr.customer_id, t.transaction_id ORDER BY cr.sent_at DESC) AS touch_rank
    FROM customer360.campaign_responses cr
    JOIN customer360.transactions t
        ON cr.customer_id = t.customer_id
        AND t.transaction_date >= cr.sent_at
        AND t.transaction_date <= cr.sent_at + INTERVAL 7 DAY
    WHERE cr.converted_at IS NOT NULL
      AND t.transaction_type = 'purchase'
)
SELECT
    campaign_type,
    count(DISTINCT customer_id) AS customers_converted,
    count(DISTINCT transaction_id) AS transactions_attributed,
    sum(total_amount) AS revenue_attributed,
    round(avg(hours_to_conversion), 2) AS avg_hours_to_conversion,

    countIf(touch_rank = 1) AS first_touch_conversions,
    countIf(touch_rank > 1) AS assisted_conversions
FROM campaign_journey
GROUP BY campaign_type
ORDER BY revenue_attributed DESC;

-- ============================================================================
-- 4.7 Customer Journey Analysis (Journey Mapping)
-- 4.7 고객 여정 분석 (Journey Mapping)
-- ============================================================================
-- Analyze customer interaction patterns (events -> transactions -> support)
-- 고객이 이벤트 -> 거래 -> 서포트 등 어떤 순서로 상호작용하는지 분석
-- ============================================================================

WITH customer_journey AS (
    SELECT
        customer_id,
        'event' AS interaction_type,
        event_type AS interaction_detail,
        event_timestamp AS interaction_time,
        0 AS interaction_value
    FROM customer360.customer_events
    WHERE customer_id % 100000 = 0

    UNION ALL

    SELECT
        customer_id,
        'transaction' AS interaction_type,
        toString(channel) AS interaction_detail,
        transaction_date AS interaction_time,
        total_amount AS interaction_value
    FROM customer360.transactions
    WHERE customer_id % 100000 = 0

    UNION ALL

    SELECT
        customer_id,
        'support' AS interaction_type,
        category AS interaction_detail,
        created_at AS interaction_time,
        0 AS interaction_value
    FROM customer360.support_tickets
    WHERE customer_id % 100000 = 0
),
journey_sequence AS (
    SELECT
        customer_id,
        interaction_type,
        interaction_detail,
        interaction_time,
        interaction_value,
        row_number() OVER (PARTITION BY customer_id ORDER BY interaction_time) AS step_number,
        lagInFrame(interaction_type) OVER (PARTITION BY customer_id ORDER BY interaction_time) AS previous_interaction
    FROM customer_journey
)
SELECT
    previous_interaction,
    interaction_type AS current_interaction,
    count() AS transition_count,
    count(DISTINCT customer_id) AS unique_customers,
    round(avg(interaction_value), 2) AS avg_value
FROM journey_sequence
WHERE previous_interaction IS NOT NULL
GROUP BY previous_interaction, current_interaction
ORDER BY transition_count DESC
LIMIT 15;
