-- ClickHouse 25.8 Feature: MinIO Integration for Data Lake
-- Purpose: Test ClickHouse 25.8 with MinIO S3-compatible storage
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08

-- ==========================================
-- Test 1: MinIO Connection Setup
-- ==========================================

SELECT '=== Test 1: MinIO Data Lake Setup ===' AS title;

SELECT '
📦 MinIO Data Lake Configuration:
   - MinIO Endpoint: http://host.docker.internal:19000
   - Console: http://localhost:19001
   - Bucket: warehouse
   - Access Key: admin
   - Secret Key: password123

This test demonstrates ClickHouse 25.8 new Parquet reader
with MinIO as S3-compatible storage backend.
' AS info;

-- ==========================================
-- Test 2: Create Sample E-commerce Data
-- ==========================================

SELECT '=== Test 2: Creating E-commerce Dataset ===' AS title;

DROP TABLE IF EXISTS ecommerce_orders;

CREATE TABLE ecommerce_orders
(
    order_id UInt64,
    order_date Date,
    order_timestamp DateTime,
    customer_id UInt32,
    customer_name String,
    customer_country String,
    customer_city String,
    product_id UInt32,
    product_name String,
    product_category String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    payment_method String,
    shipping_method String,
    order_status String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, customer_id, order_id);

-- Insert 50,000 sample orders
INSERT INTO ecommerce_orders
SELECT
    number + 1 AS order_id,
    today() - INTERVAL (number % 90) DAY AS order_date,
    now() - INTERVAL (number % 7776000) SECOND AS order_timestamp,
    (number % 5000) + 1 AS customer_id,
    concat('Customer_', toString((number % 5000) + 1)) AS customer_name,
    ['USA', 'Canada', 'UK', 'Germany', 'France', 'Japan', 'Australia', 'Brazil'][1 + (number % 8)] AS customer_country,
    concat('City_', toString((number % 100) + 1)) AS customer_city,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    ['Electronics', 'Clothing', 'Home', 'Sports', 'Books', 'Toys', 'Food', 'Beauty'][1 + (number % 8)] AS product_category,
    (number % 5) + 1 AS quantity,
    round(10 + (number % 490), 2) AS unit_price,
    round((10 + (number % 490)) * ((number % 5) + 1), 2) AS total_amount,
    ['Credit Card', 'PayPal', 'Bank Transfer', 'Cash'][1 + (number % 4)] AS payment_method,
    ['Standard', 'Express', 'Overnight'][1 + (number % 3)] AS shipping_method,
    ['Completed', 'Pending', 'Shipped', 'Cancelled'][1 + (number % 4)] AS order_status
FROM numbers(50000);

SELECT format('✅ Inserted {0} orders', count()) AS status
FROM ecommerce_orders;

-- ==========================================
-- Test 3: Export Data to MinIO (Parquet)
-- ==========================================

SELECT '=== Test 3: Exporting to MinIO as Parquet ===' AS title;

-- Enable overwrite for S3 exports
SET s3_truncate_on_insert = 1;

-- Export orders to MinIO in Parquet format
-- Using S3 table function with MinIO endpoint
INSERT INTO FUNCTION
s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
    'admin',
    'password123',
    'Parquet'
)
SELECT * FROM ecommerce_orders;

SELECT '✅ Data exported to MinIO: warehouse/ecommerce/orders/orders.parquet' AS status;

-- ==========================================
-- Test 4: Read from MinIO with New Parquet Reader
-- ==========================================

SELECT '=== Test 4: Reading from MinIO (New Parquet Reader 1.81x Faster) ===' AS title;

-- Read data from MinIO using new Parquet reader
SELECT
    count() AS total_orders,
    countIf(order_status = 'Completed') AS completed_orders,
    round(sum(total_amount), 2) AS total_revenue,
    round(avg(total_amount), 2) AS avg_order_value,
    count(DISTINCT customer_id) AS unique_customers
FROM s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
    'admin',
    'password123',
    'Parquet'
)
FORMAT Vertical;

-- ==========================================
-- Test 5: Column Pruning with MinIO
-- ==========================================

SELECT '=== Test 5: Column Pruning (99.98% Less Data Scanned) ===' AS title;

-- Only read specific columns from MinIO
SELECT
    order_date,
    product_category,
    count() AS orders,
    round(sum(total_amount), 2) AS revenue,
    round(avg(total_amount), 2) AS avg_order
FROM s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
    'admin',
    'password123',
    'Parquet'
)
WHERE order_date >= today() - INTERVAL 30 DAY
GROUP BY order_date, product_category
ORDER BY order_date DESC, revenue DESC
LIMIT 20;

SELECT '✅ New Parquet reader efficiently scanned only required columns' AS optimization;

-- ==========================================
-- Test 6: Multiple File Export to MinIO
-- ==========================================

SELECT '=== Test 6: Export by Country to MinIO ===' AS title;

-- Export USA orders
INSERT INTO FUNCTION
s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders_by_country/usa.parquet',
    'admin',
    'password123',
    'Parquet'
)
SELECT * FROM ecommerce_orders WHERE customer_country = 'USA';

-- Export UK orders
INSERT INTO FUNCTION
s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders_by_country/uk.parquet',
    'admin',
    'password123',
    'Parquet'
)
SELECT * FROM ecommerce_orders WHERE customer_country = 'UK';

SELECT '✅ Data exported to separate files by country' AS status;

-- ==========================================
-- Test 7: Query Multiple Files from MinIO
-- ==========================================

SELECT '=== Test 7: Reading Multiple Files with Wildcard ===' AS title;

-- Read from all country files using wildcard
SELECT
    customer_country,
    count() AS orders,
    round(sum(total_amount), 2) AS revenue
FROM s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders_by_country/*.parquet',
    'admin',
    'password123',
    'Parquet'
)
WHERE customer_country IN ('USA', 'UK')
GROUP BY customer_country
ORDER BY revenue DESC;

-- ==========================================
-- Test 8: Aggregated Analytics from MinIO
-- ==========================================

SELECT '=== Test 8: Daily Sales Analytics from MinIO ===' AS title;

WITH daily_stats AS (
    SELECT
        order_date,
        count() AS orders,
        round(sum(total_amount), 2) AS revenue,
        round(avg(total_amount), 2) AS avg_order,
        count(DISTINCT customer_id) AS customers
    FROM s3(
        'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
        'admin',
        'password123',
        'Parquet'
    )
    WHERE order_date >= today() - INTERVAL 14 DAY
    GROUP BY order_date
)
SELECT
    order_date,
    orders,
    revenue,
    avg_order,
    customers,
    round(revenue / customers, 2) AS revenue_per_customer
FROM daily_stats
ORDER BY order_date DESC
LIMIT 14;

-- ==========================================
-- Test 9: Product Category Performance
-- ==========================================

SELECT '=== Test 9: Product Category Analysis ===' AS title;

SELECT
    product_category,
    count() AS orders,
    sum(quantity) AS units_sold,
    round(sum(total_amount), 2) AS revenue,
    round(avg(unit_price), 2) AS avg_price,
    count(DISTINCT customer_id) AS unique_customers,
    round(sum(total_amount) / count(DISTINCT customer_id), 2) AS revenue_per_customer
FROM s3(
    'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
    'admin',
    'password123',
    'Parquet'
)
GROUP BY product_category
ORDER BY revenue DESC;

-- ==========================================
-- Test 10: Customer Segmentation from MinIO
-- ==========================================

SELECT '=== Test 10: Customer Segmentation Analysis ===' AS title;

WITH customer_stats AS (
    SELECT
        customer_id,
        customer_country,
        count() AS order_count,
        round(sum(total_amount), 2) AS lifetime_value,
        min(order_date) AS first_order,
        max(order_date) AS last_order,
        dateDiff('day', min(order_date), max(order_date)) AS customer_age_days
    FROM s3(
        'http://host.docker.internal:19000/warehouse/ecommerce/orders/orders.parquet',
        'admin',
        'password123',
        'Parquet'
    )
    GROUP BY customer_id, customer_country
)
SELECT
    CASE
        WHEN lifetime_value >= 5000 THEN 'VIP'
        WHEN lifetime_value >= 2000 THEN 'Premium'
        WHEN lifetime_value >= 500 THEN 'Regular'
        ELSE 'New'
    END AS segment,
    count() AS customers,
    round(avg(order_count), 1) AS avg_orders,
    round(avg(lifetime_value), 2) AS avg_lifetime_value,
    round(sum(lifetime_value), 2) AS total_segment_value
FROM customer_stats
GROUP BY segment
ORDER BY avg_lifetime_value DESC;

-- ==========================================
-- Test 11: Performance Summary
-- ==========================================

SELECT '=== ClickHouse 25.8 + MinIO Performance Benefits ===' AS info;

SELECT '
🚀 Performance Improvements:

1. New Parquet Reader:
   ✓ 1.81x faster reading performance
   ✓ 99.98% less data scanned with column pruning
   ✓ Efficient predicate pushdown
   ✓ Optimized memory usage

2. MinIO Integration:
   ✓ S3-compatible storage
   ✓ Local development environment
   ✓ Cost-effective data lake
   ✓ Easy scalability

3. Data Lake Features:
   ✓ Hive-style partitioning support
   ✓ Multiple format support (Parquet, ORC, Avro)
   ✓ Schema evolution
   ✓ Query federation

4. Use Cases:
   - E-commerce analytics
   - Log analysis at scale
   - Data warehouse offloading
   - Real-time dashboards
   - ML feature stores
' AS benefits;

-- Cleanup (commented out for inspection)
-- DROP TABLE ecommerce_orders;

SELECT '✅ MinIO Integration Test Complete!' AS status;
