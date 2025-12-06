-- ============================================================================
-- Customer 360 Lab Step 2: Test Data Generation
-- Customer 360 실습 Step 2: 테스트 데이터 생성
-- ============================================================================
-- Created: 2025-12-06
-- 작성일: 2025-12-06
-- Purpose: Generate test data for Customer 360 analytics
-- 목적: Customer 360 분석을 위한 테스트 데이터 생성
-- Total: 30M customers, 500M transactions, 200M events, 5M tickets, 100M campaigns, 10M reviews
-- 총: 30M 고객, 500M 거래, 200M 이벤트, 5M 티켓, 100M 캠페인, 10M 리뷰
-- ============================================================================

-- ============================================================================
-- 2.1 Customer Data Generation (30M)
-- 2.1 고객 데이터 생성 (30M)
-- ============================================================================
-- Features: Demographic data, customer segments, registration history
-- 특징: 인구통계 데이터, 고객 세그먼트, 가입 이력
-- Expected time: ~30-60 seconds
-- 예상 시간: ~30-60초
-- ============================================================================

INSERT INTO customer360.customers
SELECT
    number AS customer_id,
    concat('user', toString(number), '@example.com') AS email,
    concat('+1-', toString(1000000000 + (number % 900000000))) AS phone,
    ['John', 'Jane', 'Michael', 'Sarah', 'David', 'Emma', 'Robert', 'Lisa', 'James', 'Mary'][number % 10 + 1] AS first_name,
    ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez'][number % 10 + 1] AS last_name,
    toDate('1950-01-01') + toIntervalDay(number % 25000) AS date_of_birth,
    ['M', 'F', 'O'][number % 3 + 1] AS gender,
    ['US', 'UK', 'CA', 'AU', 'DE', 'FR', 'JP', 'KR', 'CN', 'IN'][number % 10 + 1] AS country,
    ['New York', 'London', 'Toronto', 'Sydney', 'Berlin', 'Paris', 'Tokyo', 'Seoul', 'Beijing', 'Mumbai'][number % 10 + 1] AS city,
    toString(10000 + (number % 90000)) AS postal_code,
    now() - toIntervalDay(number % 1825) AS registration_date,
    CASE
        WHEN number % 100 < 5 THEN 'VIP'
        WHEN number % 100 < 20 THEN 'Premium'
        WHEN number % 100 < 80 THEN 'Standard'
        ELSE 'New'
    END AS customer_segment,
    (number % 50000) * 1.5 AS lifetime_value,
    300 + (number % 550) AS credit_score,
    if(number % 10 < 8, true, false) AS is_active,
    now() AS last_updated
FROM numbers(30000000)
SETTINGS max_insert_threads = 8;

-- ============================================================================
-- 2.2 Transaction Data Generation (500M, 180 days - 6 months)
-- 2.2 거래 데이터 생성 (500M, 180일 - 6개월)
-- ============================================================================
-- First batch (250M) - Recent 60 days
-- 첫 번째 배치 (250M) - 최근 60일
-- Features: Purchase history, product categories, payment methods
-- 특징: 구매 이력, 제품 카테고리, 결제 수단
-- Expected time: ~5-10 minutes per batch
-- 예상 시간: 배치당 ~5-10분
-- ============================================================================

INSERT INTO customer360.transactions
SELECT
    number AS transaction_id,
    number % 30000000 AS customer_id,
    now() - toIntervalDay(60) + toIntervalSecond(number % 5184000) AS transaction_date,
    ['purchase', 'refund', 'exchange'][if(number % 100 < 95, 1, if(number % 100 < 98, 2, 3))] AS transaction_type,
    (number % 100000) + 1 AS product_id,
    ['Electronics', 'Clothing', 'Food', 'Books', 'Home', 'Sports', 'Beauty', 'Toys', 'Automotive', 'Health'][number % 10 + 1] AS product_category,
    concat('Product ', toString((number % 100000) + 1)) AS product_name,
    (number % 5) + 1 AS quantity,
    (number % 500) + 10.0 AS unit_price,
    ((number % 5) + 1) * ((number % 500) + 10.0) AS total_amount,
    if(number % 10 < 3, (number % 50) + 0.0, 0.0) AS discount_amount,
    ['Credit Card', 'Debit Card', 'PayPal', 'Apple Pay', 'Google Pay'][number % 5 + 1] AS payment_method,
    ['online', 'mobile_app', 'store', 'phone'][number % 4 + 1] AS channel,
    (number % 1000) + 1 AS store_id,
    if(number % 50 = 0, true, false) AS is_first_purchase
FROM numbers(250000000)
SETTINGS max_insert_threads = 16;

-- 두 번째 배치 (250M) - 60~180일 전
INSERT INTO customer360.transactions
SELECT
    number + 250000000 AS transaction_id,
    number % 30000000 AS customer_id,
    now() - toIntervalDay(180) + toIntervalSecond(number % 10368000) AS transaction_date,
    ['purchase', 'refund', 'exchange'][if(number % 100 < 95, 1, if(number % 100 < 98, 2, 3))] AS transaction_type,
    (number % 100000) + 1 AS product_id,
    ['Electronics', 'Clothing', 'Food', 'Books', 'Home', 'Sports', 'Beauty', 'Toys', 'Automotive', 'Health'][number % 10 + 1] AS product_category,
    concat('Product ', toString((number % 100000) + 1)) AS product_name,
    (number % 5) + 1 AS quantity,
    (number % 500) + 10.0 AS unit_price,
    ((number % 5) + 1) * ((number % 500) + 10.0) AS total_amount,
    if(number % 10 < 3, (number % 50) + 0.0, 0.0) AS discount_amount,
    ['Credit Card', 'Debit Card', 'PayPal', 'Apple Pay', 'Google Pay'][number % 5 + 1] AS payment_method,
    ['online', 'mobile_app', 'store', 'phone'][number % 4 + 1] AS channel,
    (number % 1000) + 1 AS store_id,
    if(number % 50 = 0, true, false) AS is_first_purchase
FROM numbers(250000000)
SETTINGS max_insert_threads = 16;

-- ============================================================================
-- 2.3 Customer Event Data Generation (200M, 180 days)
-- 2.3 고객 이벤트 데이터 생성 (200M, 180일)
-- ============================================================================
-- First batch (100M) - Recent 60 days
-- 첫 번째 배치 (100M) - 최근 60일
-- Features: Web/app activity, sessions, device tracking
-- 특징: 웹/앱 활동, 세션, 기기 추적
-- Expected time: ~3-5 minutes per batch
-- 예상 시간: 배치당 ~3-5분
-- ============================================================================

INSERT INTO customer360.customer_events
SELECT
    number AS event_id,
    number % 30000000 AS customer_id,
    now() - toIntervalDay(60) + toIntervalSecond(number % 5184000) AS event_timestamp,
    ['page_view', 'product_view', 'add_to_cart', 'checkout_start', 'purchase_complete', 'search', 'video_play'][number % 7 + 1] AS event_type,
    concat('https://example.com/', ['home', 'products', 'cart', 'checkout', 'account', 'search'][number % 6 + 1]) AS page_url,
    concat('session_', toString(number % 5000000)) AS session_id,
    ['desktop', 'mobile', 'tablet'][number % 3 + 1] AS device_type,
    ['Chrome', 'Safari', 'Firefox', 'Edge'][number % 4 + 1] AS browser,
    ['google', 'facebook', 'instagram', 'email', 'direct', 'twitter'][number % 6 + 1] AS referrer_source,
    (number % 600) + 1 AS duration_seconds,
    concat('{"items":', toString(number % 10), ',"value":', toString(number % 1000), '}') AS event_properties
FROM numbers(100000000)
SETTINGS max_insert_threads = 16;

-- 두 번째 배치 (100M) - 60~180일 전
INSERT INTO customer360.customer_events
SELECT
    number + 100000000 AS event_id,
    number % 30000000 AS customer_id,
    now() - toIntervalDay(180) + toIntervalSecond(number % 15552000) AS event_timestamp,
    ['page_view', 'product_view', 'add_to_cart', 'checkout_start', 'purchase_complete', 'search', 'video_play'][number % 7 + 1] AS event_type,
    concat('https://example.com/', ['home', 'products', 'cart', 'checkout', 'account', 'search'][number % 6 + 1]) AS page_url,
    concat('session_', toString(number % 5000000)) AS session_id,
    ['desktop', 'mobile', 'tablet'][number % 3 + 1] AS device_type,
    ['Chrome', 'Safari', 'Firefox', 'Edge'][number % 4 + 1] AS browser,
    ['google', 'facebook', 'instagram', 'email', 'direct', 'twitter'][number % 6 + 1] AS referrer_source,
    (number % 600) + 1 AS duration_seconds,
    concat('{"items":', toString(number % 10), ',"value":', toString(number % 1000), '}') AS event_properties
FROM numbers(100000000)
SETTINGS max_insert_threads = 16;

-- ============================================================================
-- 2.4 Support Ticket Data Generation (5M)
-- 2.4 서포트 티켓 데이터 생성 (5M)
-- ============================================================================
-- Features: Support tickets, resolution tracking, satisfaction scores
-- 특징: 지원 티켓, 해결 추적, 만족도 점수
-- Expected time: ~30-60 seconds
-- 예상 시간: ~30-60초
-- ============================================================================

INSERT INTO customer360.support_tickets
SELECT
    number AS ticket_id,
    number % 30000000 AS customer_id,
    now() - toIntervalDay(60) + toIntervalDay(number % 60) AS created_at,
    if(number % 10 < 8, now() - toIntervalDay(60) + toIntervalDay(number % 60) + toIntervalHour((number % 72) + 1), NULL) AS resolved_at,
    ['Technical Issue', 'Billing', 'Product Question', 'Shipping', 'Return', 'Account'][number % 6 + 1] AS category,
    ['low', 'medium', 'high', 'urgent'][number % 4 + 1] AS priority,
    if(number % 10 < 8, 'closed', if(number % 10 < 9, 'resolved', 'open')) AS status,
    ['email', 'phone', 'chat', 'social'][number % 4 + 1] AS channel,
    (number % 500) + 1 AS agent_id,
    if(number % 10 < 8, (number % 5) + 1, NULL) AS satisfaction_score,
    if(number % 10 < 8, (number % 72) + 0.5, NULL) AS resolution_time_hours
FROM numbers(5000000)
SETTINGS max_insert_threads = 8;

-- ============================================================================
-- 2.5 Campaign Response Data Generation (100M, 180 days)
-- 2.5 캠페인 응답 데이터 생성 (100M, 180일)
-- ============================================================================
-- First batch (50M) - Recent 60 days
-- 첫 번째 배치 (50M) - 최근 60일
-- Features: Campaign responses, open/click/conversion tracking
-- 특징: 캠페인 응답, 오픈/클릭/전환 추적
-- Expected time: ~2-3 minutes per batch
-- 예상 시간: 배치당 ~2-3분
-- ============================================================================

INSERT INTO customer360.campaign_responses
SELECT
    number AS response_id,
    number % 30000000 AS customer_id,
    (number % 100) + 1 AS campaign_id,
    concat('Campaign ', toString((number % 100) + 1)) AS campaign_name,
    ['email', 'sms', 'push', 'social', 'display'][number % 5 + 1] AS campaign_type,
    now() - toIntervalDay(60) + toIntervalHour(number % 1440) AS sent_at,
    if(number % 10 < 4, now() - toIntervalDay(60) + toIntervalHour(number % 1440) + toIntervalMinute(5), NULL) AS opened_at,
    if(number % 10 < 2, now() - toIntervalDay(60) + toIntervalHour(number % 1440) + toIntervalMinute(10), NULL) AS clicked_at,
    if(number % 100 < 5, now() - toIntervalDay(60) + toIntervalHour(number % 1440) + toIntervalHour(2), NULL) AS converted_at,
    if(number % 100 < 5, (number % 500) + 50.0, NULL) AS conversion_value
FROM numbers(50000000)
SETTINGS max_insert_threads = 16;

-- 두 번째 배치 (50M) - 60~180일 전
INSERT INTO customer360.campaign_responses
SELECT
    number + 50000000 AS response_id,
    number % 30000000 AS customer_id,
    (number % 100) + 1 AS campaign_id,
    concat('Campaign ', toString((number % 100) + 1)) AS campaign_name,
    ['email', 'sms', 'push', 'social', 'display'][number % 5 + 1] AS campaign_type,
    now() - toIntervalDay(180) + toIntervalHour(number % 4320) AS sent_at,
    if(number % 10 < 4, now() - toIntervalDay(180) + toIntervalHour(number % 4320) + toIntervalMinute(5), NULL) AS opened_at,
    if(number % 10 < 2, now() - toIntervalDay(180) + toIntervalHour(number % 4320) + toIntervalMinute(10), NULL) AS clicked_at,
    if(number % 100 < 5, now() - toIntervalDay(180) + toIntervalHour(number % 4320) + toIntervalHour(2), NULL) AS converted_at,
    if(number % 100 < 5, (number % 500) + 50.0, NULL) AS conversion_value
FROM numbers(50000000)
SETTINGS max_insert_threads = 16;

-- ============================================================================
-- 2.6 Product Review Data Generation (10M)
-- 2.6 제품 리뷰 데이터 생성 (10M)
-- ============================================================================
-- Features: Product ratings, review text, verified purchases
-- 특징: 제품 평점, 리뷰 텍스트, 검증된 구매
-- Expected time: ~30-60 seconds
-- 예상 시간: ~30-60초
-- ============================================================================

INSERT INTO customer360.product_reviews
SELECT
    number AS review_id,
    number % 30000000 AS customer_id,
    (number % 100000) + 1 AS product_id,
    (number % 5) + 1 AS rating,
    concat('This is a review for product ', toString((number % 100000) + 1), '. Overall ',
           ['terrible', 'poor', 'average', 'good', 'excellent'][number % 5 + 1], ' experience.') AS review_text,
    now() - toIntervalDay(number % 60) AS review_date,
    number % 100 AS helpful_count,
    if(number % 10 < 7, true, false) AS verified_purchase
FROM numbers(10000000)
SETTINGS max_insert_threads = 8;

-- ============================================================================
-- Verify Data Loading
-- 데이터 로드 확인
-- ============================================================================

SELECT
    name AS table_name,
    formatReadableQuantity(total_rows) AS row_count,
    formatReadableSize(total_bytes) AS compressed_size,
    formatReadableSize(total_bytes_uncompressed) AS uncompressed_size,
    round(total_bytes_uncompressed / nullIf(total_bytes, 0), 2) AS compression_ratio
FROM system.tables
WHERE database = 'customer360'
ORDER BY total_rows DESC;
