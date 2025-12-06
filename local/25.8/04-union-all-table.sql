-- ClickHouse 25.8 Feature: Enhanced UNION ALL with _table Virtual Column
-- Purpose: Test UNION ALL with _table virtual column support
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-08

-- ==========================================
-- Test 1: Create Multiple Tables for Union
-- ==========================================

SELECT '=== Test 1: Creating Multi-Region Sales Tables ===' AS title;

-- Drop tables if they exist
DROP TABLE IF EXISTS sales_us;
DROP TABLE IF EXISTS sales_eu;
DROP TABLE IF EXISTS sales_asia;
DROP TABLE IF EXISTS sales_latam;

-- US Sales
CREATE TABLE sales_us
(
    sale_id UInt64,
    sale_date Date,
    sale_time DateTime,
    customer_id UInt64,
    product_id UInt32,
    product_name String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    region String DEFAULT 'US',
    currency String DEFAULT 'USD'
)
ENGINE = MergeTree()
ORDER BY (sale_date, sale_id);

-- EU Sales
CREATE TABLE sales_eu
(
    sale_id UInt64,
    sale_date Date,
    sale_time DateTime,
    customer_id UInt64,
    product_id UInt32,
    product_name String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    region String DEFAULT 'EU',
    currency String DEFAULT 'EUR'
)
ENGINE = MergeTree()
ORDER BY (sale_date, sale_id);

-- Asia Sales
CREATE TABLE sales_asia
(
    sale_id UInt64,
    sale_date Date,
    sale_time DateTime,
    customer_id UInt64,
    product_id UInt32,
    product_name String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    region String DEFAULT 'Asia',
    currency String DEFAULT 'JPY'
)
ENGINE = MergeTree()
ORDER BY (sale_date, sale_id);

-- Latin America Sales
CREATE TABLE sales_latam
(
    sale_id UInt64,
    sale_date Date,
    sale_time DateTime,
    customer_id UInt64,
    product_id UInt32,
    product_name String,
    quantity UInt16,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2),
    region String DEFAULT 'LATAM',
    currency String DEFAULT 'BRL'
)
ENGINE = MergeTree()
ORDER BY (sale_date, sale_id);

SELECT '✅ Regional sales tables created' AS status;

-- ==========================================
-- Test 2: Insert Sample Data
-- ==========================================

SELECT '=== Test 2: Inserting Regional Sales Data ===' AS title;

-- Insert US sales
INSERT INTO sales_us
SELECT
    number + 1 AS sale_id,
    today() - INTERVAL (number % 90) DAY AS sale_date,
    now() - INTERVAL (number % 86400) SECOND AS sale_time,
    (number % 5000) + 1 AS customer_id,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    (number % 10) + 1 AS quantity,
    round((number % 200) + 20.00, 2) AS unit_price,
    round(((number % 200) + 20.00) * ((number % 10) + 1), 2) AS total_amount,
    'US' AS region,
    'USD' AS currency
FROM numbers(10000);

-- Insert EU sales
INSERT INTO sales_eu
SELECT
    number + 10001 AS sale_id,
    today() - INTERVAL (number % 90) DAY AS sale_date,
    now() - INTERVAL (number % 86400) SECOND AS sale_time,
    (number % 4000) + 5001 AS customer_id,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    (number % 10) + 1 AS quantity,
    round((number % 200) + 25.00, 2) AS unit_price,
    round(((number % 200) + 25.00) * ((number % 10) + 1), 2) AS total_amount,
    'EU' AS region,
    'EUR' AS currency
FROM numbers(8000);

-- Insert Asia sales
INSERT INTO sales_asia
SELECT
    number + 20001 AS sale_id,
    today() - INTERVAL (number % 90) DAY AS sale_date,
    now() - INTERVAL (number % 86400) SECOND AS sale_time,
    (number % 6000) + 9001 AS customer_id,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    (number % 10) + 1 AS quantity,
    round((number % 200) + 15.00, 2) AS unit_price,
    round(((number % 200) + 15.00) * ((number % 10) + 1), 2) AS total_amount,
    'Asia' AS region,
    'JPY' AS currency
FROM numbers(12000);

-- Insert LATAM sales
INSERT INTO sales_latam
SELECT
    number + 35001 AS sale_id,
    today() - INTERVAL (number % 90) DAY AS sale_date,
    now() - INTERVAL (number % 86400) SECOND AS sale_time,
    (number % 3000) + 15001 AS customer_id,
    (number % 500) + 1 AS product_id,
    concat('Product_', toString((number % 500) + 1)) AS product_name,
    (number % 10) + 1 AS quantity,
    round((number % 200) + 18.00, 2) AS unit_price,
    round(((number % 200) + 18.00) * ((number % 10) + 1), 2) AS total_amount,
    'LATAM' AS region,
    'BRL' AS currency
FROM numbers(6000);

SELECT '✅ Sample data inserted' AS status;
SELECT 'US: ' || formatReadableQuantity(count()) || ' rows' AS us_sales FROM sales_us;
SELECT 'EU: ' || formatReadableQuantity(count()) || ' rows' AS eu_sales FROM sales_eu;
SELECT 'Asia: ' || formatReadableQuantity(count()) || ' rows' AS asia_sales FROM sales_asia;
SELECT 'LATAM: ' || formatReadableQuantity(count()) || ' rows' AS latam_sales FROM sales_latam;

-- ==========================================
-- Test 3: Basic UNION ALL with _table Column
-- ==========================================

SELECT '=== Test 3: UNION ALL with _table Virtual Column ===' AS title;

-- Query with _table column to identify source table
SELECT
    _table AS source_table,
    count() AS sales_count,
    round(sum(total_amount), 2) AS total_revenue,
    round(avg(total_amount), 2) AS avg_sale,
    count(DISTINCT customer_id) AS unique_customers
FROM
(
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
GROUP BY source_table
ORDER BY total_revenue DESC;

SELECT '✅ _table virtual column tracks source table' AS feature;

-- ==========================================
-- Test 4: Global Sales Analysis
-- ==========================================

SELECT '=== Test 4: Global Sales Summary ===' AS title;

-- Combined analysis across all regions
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    count() AS total_sales,
    count(DISTINCT _table) AS regions,
    count(DISTINCT customer_id) AS total_customers,
    count(DISTINCT product_id) AS total_products,
    round(sum(total_amount), 2) AS global_revenue,
    round(avg(total_amount), 2) AS avg_transaction,
    min(sale_date) AS earliest_sale,
    max(sale_date) AS latest_sale
FROM all_sales
FORMAT Vertical;

-- ==========================================
-- Test 5: Daily Sales by Region
-- ==========================================

SELECT '=== Test 5: Daily Sales Trend by Region ===' AS title;

-- Daily comparison across regions using _table
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    sale_date,
    _table AS source_region,
    count() AS daily_sales,
    round(sum(total_amount), 2) AS daily_revenue,
    count(DISTINCT customer_id) AS unique_customers
FROM all_sales
WHERE sale_date >= today() - INTERVAL 7 DAY
GROUP BY sale_date, _table
ORDER BY sale_date DESC, daily_revenue DESC
LIMIT 28;

-- ==========================================
-- Test 6: Product Performance Across Regions
-- ==========================================

SELECT '=== Test 6: Top Products by Region ===' AS title;

-- Top products with source table identification
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    product_id,
    product_name,
    _table AS source_region,
    count() AS sales,
    sum(quantity) AS units_sold,
    round(sum(total_amount), 2) AS revenue,
    round(avg(unit_price), 2) AS avg_price
FROM all_sales
GROUP BY product_id, product_name, _table
ORDER BY revenue DESC
LIMIT 20;

-- ==========================================
-- Test 7: Customer Distribution
-- ==========================================

SELECT '=== Test 7: Customer Distribution Across Regions ===' AS title;

-- Customer purchase patterns by source table
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    _table AS source_region,
    customer_id,
    count() AS purchases,
    sum(quantity) AS total_items,
    round(sum(total_amount), 2) AS lifetime_value,
    round(avg(total_amount), 2) AS avg_purchase,
    min(sale_date) AS first_purchase,
    max(sale_date) AS last_purchase
FROM all_sales
GROUP BY _table, customer_id
HAVING lifetime_value > 1000
ORDER BY lifetime_value DESC
LIMIT 30;

-- ==========================================
-- Test 8: Filtering by Source Table
-- ==========================================

SELECT '=== Test 8: Filter Results by Source Table ===' AS title;

-- Filter union results by source table
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    sale_date,
    _table AS source_region,
    count() AS sales,
    round(sum(total_amount), 2) AS revenue
FROM all_sales
WHERE _table IN ('sales_us', 'sales_eu')  -- Filter to specific regions
GROUP BY sale_date, _table
ORDER BY sale_date DESC, revenue DESC
LIMIT 20;

SELECT '✅ _table column enables filtering by source' AS feature;

-- ==========================================
-- Test 9: Cross-Region Comparison
-- ==========================================

SELECT '=== Test 9: Cross-Region Performance Comparison ===' AS title;

-- Side-by-side region comparison
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
),
region_metrics AS (
    SELECT
        _table AS region,
        count() AS total_sales,
        round(sum(total_amount), 2) AS revenue,
        count(DISTINCT customer_id) AS customers,
        round(avg(total_amount), 2) AS avg_sale
    FROM all_sales
    GROUP BY _table
)
SELECT
    region,
    total_sales,
    revenue,
    customers,
    avg_sale,
    round(revenue / (SELECT sum(revenue) FROM region_metrics) * 100, 2) AS revenue_share_pct,
    round(customers / (SELECT sum(customers) FROM region_metrics) * 100, 2) AS customer_share_pct
FROM region_metrics
ORDER BY revenue DESC;

-- ==========================================
-- Test 10: Time-Based Analysis
-- ==========================================

SELECT '=== Test 10: Weekly Trend by Source Table ===' AS title;

-- Weekly aggregation with source tracking
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    toStartOfWeek(sale_date) AS week_start,
    _table AS source_region,
    count() AS weekly_sales,
    round(sum(total_amount), 2) AS weekly_revenue,
    count(DISTINCT customer_id) AS unique_customers,
    round(avg(total_amount), 2) AS avg_transaction
FROM all_sales
GROUP BY week_start, _table
ORDER BY week_start DESC, weekly_revenue DESC
LIMIT 40;

-- ==========================================
-- Test 11: Data Lineage and Audit
-- ==========================================

SELECT '=== Test 11: Data Lineage with _table Column ===' AS title;

-- Track which table contributed to results
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
),
large_transactions AS (
    SELECT
        sale_id,
        _table AS source_table,
        sale_date,
        customer_id,
        product_name,
        quantity,
        total_amount,
        region,
        currency
    FROM all_sales
    WHERE total_amount > 500
    ORDER BY total_amount DESC
    LIMIT 50
)
SELECT
    source_table,
    count() AS large_transactions,
    round(sum(total_amount), 2) AS total_value,
    round(avg(total_amount), 2) AS avg_value,
    arrayStringConcat(groupArray(region), ', ') AS regions
FROM large_transactions
GROUP BY source_table
ORDER BY total_value DESC;

SELECT '✅ _table column provides data lineage tracking' AS benefit;

-- ==========================================
-- Test 12: Multi-Currency Aggregation
-- ==========================================

SELECT '=== Test 12: Multi-Currency Revenue Tracking ===' AS title;

-- Track revenue by currency and source
WITH all_sales AS (
    SELECT *, 'sales_us' AS _table FROM sales_us
    UNION ALL
    SELECT *, 'sales_eu' AS _table FROM sales_eu
    UNION ALL
    SELECT *, 'sales_asia' AS _table FROM sales_asia
    UNION ALL
    SELECT *, 'sales_latam' AS _table FROM sales_latam
)
SELECT
    _table AS source_region,
    currency,
    count() AS transactions,
    round(sum(total_amount), 2) AS revenue_in_currency,
    round(avg(total_amount), 2) AS avg_transaction,
    count(DISTINCT customer_id) AS customers
FROM all_sales
GROUP BY _table, currency
ORDER BY _table, revenue_in_currency DESC;

-- ==========================================
-- Performance Summary
-- ==========================================

SELECT '=== Enhanced UNION ALL Summary ===' AS title;

SELECT '
✅ Enhanced UNION ALL with _table Virtual Column in ClickHouse 25.8:

1. _table Virtual Column:
   - Identifies source table in UNION ALL results
   - Available in query results
   - Can be used in WHERE, GROUP BY, ORDER BY

2. Key Benefits:
   ✓ Data lineage tracking
   ✓ Source identification in merged results
   ✓ Filtering by source table
   ✓ Aggregation by source
   ✓ Audit trail for multi-table queries

3. Use Cases:
   📊 Multi-region data consolidation
   📊 Historical data (yearly tables union)
   📊 Multi-tenant data queries
   📊 Federated query results
   📊 Data migration validation
   📊 Cross-shard analytics

4. Syntax:
   SELECT *, ''table_name'' AS _table FROM table1
   UNION ALL
   SELECT *, ''table_name2'' AS _table FROM table2

5. Query Capabilities:
   - Filter: WHERE _table = ''sales_us''
   - Group: GROUP BY _table
   - Order: ORDER BY _table, revenue DESC
   - Aggregate: count(DISTINCT _table)

6. Real-World Examples:
   ✓ E-commerce: Multi-region sales analysis
   ✓ SaaS: Multi-tenant reporting
   ✓ Finance: Cross-entity consolidation
   ✓ Logs: Multi-source log analysis
   ✓ IoT: Multi-location device data
   ✓ Data Lake: Multi-table federation

💡 Best Practices:
- Use meaningful table identifiers
- Include _table in GROUP BY for source tracking
- Filter by _table for partition pruning
- Document data lineage in queries
- Use for auditing and compliance

🎯 Performance Notes:
- _table column adds minimal overhead
- Enables source-based optimizations
- Useful for debugging multi-table queries
- Supports data governance requirements
' AS summary;

-- Optional: Cleanup (commented out by default)
-- DROP TABLE IF EXISTS sales_us;
-- DROP TABLE IF EXISTS sales_eu;
-- DROP TABLE IF EXISTS sales_asia;
-- DROP TABLE IF EXISTS sales_latam;
-- SELECT '🧹 Cleanup completed' AS status;
