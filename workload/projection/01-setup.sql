-- ============================================
-- ClickHouse Projection Lab - Setup
-- 1. 테스트 환경 준비 및 데이터 생성
-- ============================================

-- 테스트 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS projection_test;

-- 원본 테이블 생성 (1000만 건의 이벤트 데이터)
CREATE TABLE IF NOT EXISTS projection_test.sales_events
(
    event_id UInt64,
    event_time DateTime,
    user_id UInt32,
    product_id UInt32,
    category String,
    brand String,
    price Decimal(10, 2),
    quantity UInt16,
    discount_rate Float32,
    payment_method String,
    country String,
    city String,
    device_type String,
    session_duration UInt32,
    page_views UInt16,
    is_mobile UInt8,
    customer_segment String,
    revenue Decimal(10, 2)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id, product_id);

-- 테스트 데이터 생성 (1000만 건)
INSERT INTO projection_test.sales_events
SELECT
    number AS event_id,
    toDateTime('2024-01-01 00:00:00') + toIntervalSecond(number % (365 * 86400)) AS event_time,
    number % 1000000 AS user_id,
    number % 50000 AS product_id,
    ['Electronics', 'Clothing', 'Food', 'Home', 'Sports', 'Books', 'Toys', 'Beauty', 'Automotive', 'Garden'][number % 10 + 1] AS category,
    concat('Brand_', toString(number % 500)) AS brand,
    round(rand() % 50000 / 100, 2) AS price,
    (rand() % 10) + 1 AS quantity,
    round((rand() % 50) / 100, 2) AS discount_rate,
    ['Credit Card', 'PayPal', 'Bank Transfer', 'Cash', 'Crypto'][number % 5 + 1] AS payment_method,
    ['USA', 'UK', 'Germany', 'France', 'Japan', 'Korea', 'China', 'India', 'Brazil', 'Australia'][number % 10 + 1] AS country,
    concat('City_', toString(number % 1000)) AS city,
    ['Desktop', 'Mobile', 'Tablet'][number % 3 + 1] AS device_type,
    (rand() % 3600) + 60 AS session_duration,
    (rand() % 50) + 1 AS page_views,
    number % 2 AS is_mobile,
    ['Premium', 'Standard', 'Basic', 'VIP'][number % 4 + 1] AS customer_segment,
    round(price * quantity * (1 - discount_rate), 2) AS revenue
FROM numbers(10000000);

-- 데이터 확인
SELECT
    count() as total_rows,
    min(event_time) as min_date,
    max(event_time) as max_date,
    sum(revenue) as total_revenue,
    avg(price) as avg_price
FROM projection_test.sales_events;
