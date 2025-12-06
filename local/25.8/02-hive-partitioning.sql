-- ClickHouse 25.8 Feature: Hive-Style Partitioning
-- Purpose: Test hive-style partitioning with partition_strategy parameter
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08

-- ==========================================
-- Test 1: Create Sample Sales Data
-- ==========================================

SELECT '=== Test 1: Creating Sales Transaction Dataset ===' AS title;

DROP TABLE IF EXISTS sales_transactions;

CREATE TABLE sales_transactions
(
    transaction_id UInt64,
    transaction_date Date,
    transaction_time DateTime,
    store_id UInt32,
    store_name String,
    store_region String,
    customer_id UInt64,
    product_id UInt32,
    product_name String,
    product_category String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    discount_amount Decimal(10, 2),
    payment_method String,
    year UInt16,
    month UInt8,
    day UInt8
)
ENGINE = MergeTree()
PARTITION BY (year, month)
ORDER BY (transaction_date, transaction_id);

-- Insert sample sales data
INSERT INTO sales_transactions
SELECT
    number + 1 AS transaction_id,
    today() - INTERVAL (number % 365) DAY AS transaction_date,
    now() - INTERVAL (number % 86400) SECOND AS transaction_time,
    (number % 50) + 1 AS store_id,
    concat('Store_', toString((number % 50) + 1)) AS store_name,
    ['North', 'South', 'East', 'West', 'Central'][1 + (number % 5)] AS store_region,
    (number % 5000) + 1 AS customer_id,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    ['Electronics', 'Clothing', 'Food', 'Home', 'Sports', 'Books'][1 + (number % 6)] AS product_category,
    (number % 10) + 1 AS quantity,
    round((number % 200) + 10.00, 2) AS unit_price,
    round(((number % 200) + 10.00) * ((number % 10) + 1), 2) AS total_amount,
    round((((number % 200) + 10.00) * ((number % 10) + 1)) * 0.05, 2) AS discount_amount,
    ['Cash', 'Credit Card', 'Debit Card', 'Mobile Payment', 'Gift Card'][1 + (number % 5)] AS payment_method,
    toYear(transaction_date) AS year,
    toMonth(transaction_date) AS month,
    toDayOfMonth(transaction_date) AS day
FROM numbers(100000);

SELECT format('✅ Inserted {0} rows into sales_transactions', count()) AS status
FROM sales_transactions;

-- ==========================================
-- Test 2: Export with Hive-Style Partitioning
-- ==========================================

SELECT '=== Test 2: Export Data with Hive-Style Partitioning ===' AS title;

-- Export to Parquet files with Hive partitioning (year=YYYY/month=MM/)
INSERT INTO FUNCTION file('/tmp/sales_hive/{year}/month={month}/*.parquet', 'Parquet')
SELECT
    transaction_id,
    transaction_date,
    transaction_time,
    store_id,
    store_name,
    store_region,
    customer_id,
    product_id,
    product_name,
    product_category,
    quantity,
    unit_price,
    total_amount,
    discount_amount,
    payment_method,
    day,
    year,
    month
FROM sales_transactions;

SELECT '✅ Data exported with Hive-style partitioning to /tmp/sales_hive/' AS status;
SELECT '   Directory structure: /tmp/sales_hive/{year}/month={month}/*.parquet' AS info;

-- ==========================================
-- Test 3: Read Hive-Partitioned Data
-- ==========================================

SELECT '=== Test 3: Reading Hive-Partitioned Data ===' AS title;

-- Read all data from Hive-partitioned directory
SELECT
    count() AS total_transactions,
    count(DISTINCT year) AS years,
    count(DISTINCT month) AS months,
    round(sum(total_amount), 2) AS total_sales,
    round(avg(total_amount), 2) AS avg_transaction
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
FORMAT Vertical;

-- ==========================================
-- Test 4: Partition Pruning (Read Specific Partitions)
-- ==========================================

SELECT '=== Test 4: Partition Pruning (Read Specific Year/Month) ===' AS title;

-- Only read data from specific partitions (efficient!)
SELECT
    year,
    month,
    count() AS transactions,
    round(sum(total_amount), 2) AS monthly_sales,
    round(avg(total_amount), 2) AS avg_transaction
FROM file('/tmp/sales_hive/*/month=*/*.parquet', 'Parquet')
WHERE year = toYear(today()) AND month >= toMonth(today()) - 2
GROUP BY year, month
ORDER BY year DESC, month DESC;

SELECT '✅ Partition pruning only scanned required month directories' AS optimization;

-- ==========================================
-- Test 5: Regional Sales Analysis
-- ==========================================

SELECT '=== Test 5: Regional Sales Analysis by Month ===' AS title;

-- Analyze sales by region using Hive-partitioned data
SELECT
    year,
    month,
    store_region,
    count() AS transactions,
    round(sum(total_amount), 2) AS region_sales,
    round(avg(total_amount), 2) AS avg_transaction,
    count(DISTINCT customer_id) AS unique_customers
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE year = toYear(today())
GROUP BY year, month, store_region
ORDER BY year DESC, month DESC, region_sales DESC
LIMIT 20;

-- ==========================================
-- Test 6: Product Category Performance
-- ==========================================

SELECT '=== Test 6: Product Category Performance by Quarter ===' AS title;

-- Quarterly analysis by category
SELECT
    year,
    quarter(toDate(concat(toString(year), '-', toString(month), '-01'))) AS quarter,
    product_category,
    count() AS transactions,
    sum(quantity) AS units_sold,
    round(sum(total_amount), 2) AS category_revenue,
    round(avg(unit_price), 2) AS avg_price
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
GROUP BY year, quarter, product_category
ORDER BY year DESC, quarter DESC, category_revenue DESC
LIMIT 20;

-- ==========================================
-- Test 7: Store Performance Ranking
-- ==========================================

SELECT '=== Test 7: Top Performing Stores by Month ===' AS title;

-- Top stores per month
SELECT
    year,
    month,
    store_id,
    store_name,
    store_region,
    count() AS transactions,
    round(sum(total_amount), 2) AS store_revenue,
    count(DISTINCT customer_id) AS unique_customers,
    round(avg(total_amount), 2) AS avg_transaction
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE year = toYear(today())
GROUP BY year, month, store_id, store_name, store_region
ORDER BY year DESC, month DESC, store_revenue DESC
LIMIT 15;

-- ==========================================
-- Test 8: Payment Method Analysis
-- ==========================================

SELECT '=== Test 8: Payment Method Distribution ===' AS title;

-- Payment method preferences by month
SELECT
    year,
    month,
    payment_method,
    count() AS transactions,
    round(sum(total_amount), 2) AS payment_revenue,
    round(count() / sum(count()) OVER (PARTITION BY year, month) * 100, 2) AS percentage
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE year = toYear(today())
GROUP BY year, month, payment_method
ORDER BY year DESC, month DESC, payment_revenue DESC;

-- ==========================================
-- Test 9: Daily Sales Trend
-- ==========================================

SELECT '=== Test 9: Daily Sales Trend (Last 30 Days) ===' AS title;

-- Daily trend analysis
SELECT
    transaction_date,
    count() AS transactions,
    round(sum(total_amount), 2) AS daily_revenue,
    round(sum(discount_amount), 2) AS total_discounts,
    round(avg(total_amount), 2) AS avg_transaction,
    count(DISTINCT customer_id) AS unique_customers,
    count(DISTINCT store_id) AS active_stores
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE transaction_date >= today() - INTERVAL 30 DAY
GROUP BY transaction_date
ORDER BY transaction_date DESC;

-- ==========================================
-- Test 10: Customer Purchase Patterns
-- ==========================================

SELECT '=== Test 10: High-Value Customer Analysis ===' AS title;

-- Identify high-value customers
SELECT
    customer_id,
    count() AS purchases,
    sum(quantity) AS total_items,
    round(sum(total_amount), 2) AS lifetime_value,
    round(avg(total_amount), 2) AS avg_purchase,
    count(DISTINCT product_category) AS categories_purchased,
    arrayStringConcat(groupArray(DISTINCT payment_method), ', ') AS payment_methods
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE year = toYear(today())
GROUP BY customer_id
HAVING lifetime_value > 1000
ORDER BY lifetime_value DESC
LIMIT 20;

-- ==========================================
-- Test 11: Demonstrate Partition Efficiency
-- ==========================================

SELECT '=== Test 11: Partition Efficiency Comparison ===' AS title;

-- Efficient: Read only specific partitions
SELECT '--- Efficient Query: Specific Month Partitions ---' AS query_type;
SELECT
    count() AS transactions,
    round(sum(total_amount), 2) AS revenue
FROM file('/tmp/sales_hive/*/month={01,02,03}/*.parquet', 'Parquet')
WHERE year = toYear(today());

-- Less efficient: Scan all partitions with filter
SELECT '--- Full Scan: All Partitions with WHERE filter ---' AS query_type;
SELECT
    count() AS transactions,
    round(sum(total_amount), 2) AS revenue
FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
WHERE year = toYear(today()) AND month IN (1, 2, 3);

SELECT '✅ Hive partitioning allows directory-level partition pruning!' AS optimization;

-- ==========================================
-- Test 12: Time-Series Analysis
-- ==========================================

SELECT '=== Test 12: Month-over-Month Growth Analysis ===' AS title;

-- Month-over-month comparison
WITH monthly_sales AS (
    SELECT
        year,
        month,
        round(sum(total_amount), 2) AS revenue,
        count() AS transactions,
        count(DISTINCT customer_id) AS customers
    FROM file('/tmp/sales_hive/*/*/*', 'Parquet')
    GROUP BY year, month
)
SELECT
    year,
    month,
    revenue,
    transactions,
    customers,
    round((revenue - lagInFrame(revenue) OVER (ORDER BY year, month)) / lagInFrame(revenue) OVER (ORDER BY year, month) * 100, 2) AS revenue_growth_pct,
    transactions - lagInFrame(transactions) OVER (ORDER BY year, month) AS transaction_growth,
    customers - lagInFrame(customers) OVER (ORDER BY year, month) AS customer_growth
FROM monthly_sales
ORDER BY year DESC, month DESC
LIMIT 12;

-- ==========================================
-- Performance Summary
-- ==========================================

SELECT '=== Hive-Style Partitioning Summary ===' AS title;

SELECT '
✅ Hive-Style Partitioning Features in ClickHouse 25.8:

1. Directory Structure: Data organized in key=value directories
   Example: /path/year=2024/month=12/day=01/

2. Partition Pruning: Only scan relevant directories
   Benefit: Drastically reduces data scanning

3. Compatibility: Standard Hive partitioning scheme
   Compatible with: Spark, Presto, Athena, etc.

4. Flexible Patterns: Support multiple partition levels
   Examples:
   - /data/year=YYYY/month=MM/
   - /data/country=US/region=West/
   - /data/date=YYYY-MM-DD/hour=HH/

5. Automatic Detection: ClickHouse auto-detects partition columns
   No schema changes needed!

📊 Use Cases:
- Data Lake organization (S3, HDFS, GCS)
- Multi-engine data sharing (Spark + ClickHouse)
- Time-series data management
- Geographic data partitioning
- Multi-tenant data isolation
- ETL pipeline optimization

🚀 Performance Benefits:
- Reduced I/O: Skip irrelevant partitions
- Faster queries: Read only needed data
- Better organization: Intuitive directory structure
- Scalability: Handle petabytes efficiently
' AS summary;

-- Optional: Cleanup (commented out by default)
-- DROP TABLE IF EXISTS sales_transactions;
-- SELECT '🧹 Cleanup completed' AS status;
