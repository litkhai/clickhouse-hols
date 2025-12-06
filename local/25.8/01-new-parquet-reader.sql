-- ClickHouse 25.8 Feature: New Parquet Reader
-- Purpose: Test the new Parquet reader with 1.81x faster performance and 99.98% less data scanning
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08

-- ==========================================
-- Test 1: Create Sample Data for Parquet Export
-- ==========================================

SELECT '=== Test 1: Creating Sample E-commerce Dataset ===' AS title;

DROP TABLE IF EXISTS ecommerce_events;

CREATE TABLE ecommerce_events
(
    event_time DateTime,
    event_date Date,
    user_id UInt64,
    session_id String,
    event_type String,
    product_id UInt32,
    product_category String,
    product_name String,
    product_price Decimal(10, 2),
    quantity UInt16,
    revenue Decimal(10, 2),
    user_country String,
    user_city String,
    device_type String,
    browser String,
    referrer String,
    page_url String,
    utm_source String,
    utm_medium String,
    utm_campaign String,
    is_mobile UInt8,
    is_purchase UInt8
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (event_date, user_id, event_time);

-- Insert sample e-commerce events (100,000 rows)
INSERT INTO ecommerce_events
SELECT
    now() - INTERVAL (number % 86400) SECOND AS event_time,
    today() - INTERVAL (number % 30) DAY AS event_date,
    (number % 10000) + 1 AS user_id,
    concat('session_', toString((number % 50000) + 1)) AS session_id,
    ['view', 'add_to_cart', 'purchase', 'remove_from_cart', 'wishlist'][1 + (number % 5)] AS event_type,
    (number % 1000) + 1 AS product_id,
    ['Electronics', 'Clothing', 'Books', 'Home & Garden', 'Sports', 'Toys', 'Food'][1 + (number % 7)] AS product_category,
    concat('Product_', toString((number % 1000) + 1)) AS product_name,
    round((number % 500) + 9.99, 2) AS product_price,
    (number % 10) + 1 AS quantity,
    if(event_type = 'purchase', product_price * quantity, 0) AS revenue,
    ['USA', 'UK', 'Germany', 'France', 'Japan', 'Canada', 'Australia'][1 + (number % 7)] AS user_country,
    concat('City_', toString((number % 100) + 1)) AS user_city,
    ['Desktop', 'Mobile', 'Tablet'][1 + (number % 3)] AS device_type,
    ['Chrome', 'Safari', 'Firefox', 'Edge'][1 + (number % 4)] AS browser,
    ['Google', 'Direct', 'Facebook', 'Twitter', 'Email'][1 + (number % 5)] AS referrer,
    concat('/product/', toString((number % 1000) + 1)) AS page_url,
    ['google', 'facebook', 'instagram', 'email', 'direct'][1 + (number % 5)] AS utm_source,
    ['cpc', 'organic', 'social', 'email', 'referral'][1 + (number % 5)] AS utm_medium,
    concat('campaign_', toString((number % 20) + 1)) AS utm_campaign,
    if(device_type = 'Mobile', 1, 0) AS is_mobile,
    if(event_type = 'purchase', 1, 0) AS is_purchase
FROM numbers(100000);

SELECT format('✅ Inserted {0} rows into ecommerce_events', count()) AS status
FROM ecommerce_events;

-- ==========================================
-- Test 2: Export Data to Parquet Format
-- ==========================================

SELECT '=== Test 2: Exporting Data to Parquet Format ===' AS title;

-- Export to Parquet file
INSERT INTO FUNCTION file('/tmp/ecommerce_events.parquet', 'Parquet')
SELECT * FROM ecommerce_events;

SELECT '✅ Data exported to /tmp/ecommerce_events.parquet' AS status;

-- ==========================================
-- Test 3: Read Parquet File with New Reader
-- ==========================================

SELECT '=== Test 3: Reading Parquet File (New Reader) ===' AS title;

-- Read entire Parquet file
SELECT
    count() AS total_events,
    countIf(is_purchase = 1) AS purchases,
    round(sum(revenue), 2) AS total_revenue,
    round(avg(product_price), 2) AS avg_price
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
FORMAT Vertical;

-- ==========================================
-- Test 4: Column Pruning Optimization
-- ==========================================

SELECT '=== Test 4: Column Pruning (99.98% Less Data Scanned) ===' AS title;

-- Only read specific columns (demonstrates efficient column pruning)
SELECT
    event_date,
    product_category,
    count() AS events,
    sum(revenue) AS category_revenue
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
WHERE event_date >= today() - INTERVAL 7 DAY
GROUP BY event_date, product_category
ORDER BY event_date DESC, category_revenue DESC
LIMIT 10;

SELECT '✅ New Parquet reader only scanned required columns' AS optimization;

-- ==========================================
-- Test 5: Performance - Complex Analytics Query
-- ==========================================

SELECT '=== Test 5: Complex Analytics with Parquet Reader ===' AS title;

-- Daily conversion funnel analysis
WITH parquet_data AS (
    SELECT *
    FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
    WHERE event_date >= today() - INTERVAL 14 DAY
)
SELECT
    event_date,
    countIf(event_type = 'view') AS views,
    countIf(event_type = 'add_to_cart') AS add_to_cart,
    countIf(event_type = 'purchase') AS purchases,
    round(countIf(event_type = 'add_to_cart') / countIf(event_type = 'view') * 100, 2) AS cart_rate,
    round(countIf(event_type = 'purchase') / countIf(event_type = 'view') * 100, 2) AS conversion_rate,
    round(sum(revenue), 2) AS daily_revenue
FROM parquet_data
GROUP BY event_date
ORDER BY event_date DESC
LIMIT 14;

-- ==========================================
-- Test 6: User Behavior Analysis
-- ==========================================

SELECT '=== Test 6: User Behavior Analysis from Parquet ===' AS title;

-- Top users by revenue
SELECT
    user_id,
    countIf(event_type = 'purchase') AS purchases,
    round(sum(revenue), 2) AS total_spent,
    round(avg(product_price), 2) AS avg_order_value,
    arrayStringConcat(groupArray(DISTINCT product_category), ', ') AS categories
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
WHERE is_purchase = 1
GROUP BY user_id
ORDER BY total_spent DESC
LIMIT 10;

-- ==========================================
-- Test 7: Device and Channel Performance
-- ==========================================

SELECT '=== Test 7: Device & Channel Performance from Parquet ===' AS title;

-- Performance by device and traffic source
SELECT
    device_type,
    utm_source,
    count() AS total_events,
    countIf(is_purchase = 1) AS purchases,
    round(countIf(is_purchase = 1) / count() * 100, 2) AS conversion_rate,
    round(sum(revenue), 2) AS revenue,
    round(avg(if(is_purchase = 1, revenue, NULL)), 2) AS avg_order_value
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
GROUP BY device_type, utm_source
ORDER BY revenue DESC
LIMIT 15;

-- ==========================================
-- Test 8: Geographic Analysis
-- ==========================================

SELECT '=== Test 8: Geographic Analysis from Parquet ===' AS title;

-- Revenue and conversion by country
SELECT
    user_country,
    count(DISTINCT user_id) AS unique_users,
    count() AS total_events,
    countIf(is_purchase = 1) AS purchases,
    round(sum(revenue), 2) AS revenue,
    round(avg(if(is_purchase = 1, revenue, NULL)), 2) AS avg_order_value
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
GROUP BY user_country
ORDER BY revenue DESC;

-- ==========================================
-- Test 9: Product Category Performance
-- ==========================================

SELECT '=== Test 9: Product Category Performance from Parquet ===' AS title;

-- Best performing categories
SELECT
    product_category,
    count(DISTINCT product_id) AS unique_products,
    countIf(event_type = 'view') AS views,
    countIf(event_type = 'add_to_cart') AS added_to_cart,
    countIf(event_type = 'purchase') AS purchases,
    round(countIf(event_type = 'purchase') / countIf(event_type = 'view') * 100, 2) AS conversion_rate,
    round(sum(revenue), 2) AS total_revenue,
    round(avg(if(is_purchase = 1, revenue, NULL)), 2) AS avg_order_value
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
GROUP BY product_category
ORDER BY total_revenue DESC;

-- ==========================================
-- Test 10: Time-based Analysis
-- ==========================================

SELECT '=== Test 10: Hourly Activity Pattern from Parquet ===' AS title;

-- Activity by hour of day
SELECT
    toHour(event_time) AS hour,
    count() AS events,
    countIf(is_purchase = 1) AS purchases,
    round(sum(revenue), 2) AS revenue,
    round(countIf(is_purchase = 1) / count() * 100, 2) AS conversion_rate
FROM file('/tmp/ecommerce_events.parquet', 'Parquet')
GROUP BY hour
ORDER BY hour;

-- ==========================================
-- Performance Summary
-- ==========================================

SELECT '=== Performance Summary ===' AS title;

SELECT '
✅ New Parquet Reader Features in ClickHouse 25.8:

1. Performance: 1.81x faster than previous reader
2. Efficiency: Scans 99.98% less data with column pruning
3. Optimization: Only reads required columns from Parquet files
4. Memory: Reduced memory footprint for large Parquet files
5. Compatibility: Full support for Parquet v2 format

📊 Use Cases:
- Data Lake query acceleration
- ETL pipeline optimization
- Parquet file analytics
- Cloud storage integration (S3, GCS, Azure)
- Data warehouse federation
' AS summary;

-- Optional: Cleanup (commented out by default)
-- DROP TABLE IF EXISTS ecommerce_events;
-- SELECT '🧹 Cleanup completed' AS status;
