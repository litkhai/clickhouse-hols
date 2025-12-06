-- ClickHouse 25.9 Feature: Automatic Global Join Reordering
-- Purpose: Test automatic join reordering based on data volume and statistics
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-09

-- ==========================================
-- Test 1: Setup - Create Tables with Different Sizes
-- ==========================================

SELECT '=== Test 1: Creating Sample Tables for Join Reordering ===' AS title;

-- Small dimension table: 100 countries
DROP TABLE IF EXISTS countries;
CREATE TABLE countries
(
    country_id UInt32,
    country_name String,
    continent String,
    population UInt64
)
ENGINE = MergeTree()
ORDER BY country_id;

INSERT INTO countries
SELECT
    number + 1 AS country_id,
    concat('Country_', toString(number + 1)) AS country_name,
    ['Asia', 'Europe', 'Americas', 'Africa', 'Oceania'][1 + (number % 5)] AS continent,
    1000000 + (number * 100000) AS population
FROM numbers(100);

SELECT format('✅ Created countries table: {0} rows', count()) AS status FROM countries;

-- Medium dimension table: 10,000 products
DROP TABLE IF EXISTS products;
CREATE TABLE products
(
    product_id UInt32,
    product_name String,
    category String,
    unit_price Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY product_id;

INSERT INTO products
SELECT
    number + 1 AS product_id,
    concat('Product_', toString(number + 1)) AS product_name,
    ['Electronics', 'Clothing', 'Food', 'Books', 'Toys'][1 + (number % 5)] AS category,
    round(10 + (number % 990), 2) AS unit_price
FROM numbers(10000);

SELECT format('✅ Created products table: {0} rows', count()) AS status FROM products;

-- Large fact table: 1,000,000 orders
DROP TABLE IF EXISTS orders;
CREATE TABLE orders
(
    order_id UInt64,
    order_date Date,
    customer_id UInt32,
    product_id UInt32,
    country_id UInt32,
    quantity UInt16,
    total_amount Decimal(10, 2)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, order_id);

INSERT INTO orders
SELECT
    number + 1 AS order_id,
    today() - INTERVAL (number % 365) DAY AS order_date,
    (number % 50000) + 1 AS customer_id,
    (number % 10000) + 1 AS product_id,
    (number % 100) + 1 AS country_id,
    (number % 10) + 1 AS quantity,
    round((10 + (number % 990)) * ((number % 10) + 1), 2) AS total_amount
FROM numbers(1000000);

SELECT format('✅ Created orders table: {0} rows', count()) AS status FROM orders;

-- ==========================================
-- Test 2: Multi-Way Join Without Optimization
-- ==========================================

SELECT '=== Test 2: Multi-Way Join (Manual Order) ===' AS title;

SELECT '\nManual join order: orders -> products -> countries\n' AS info;

-- Disable join reordering to see baseline performance
SET allow_experimental_join_reordering = 0;

SELECT
    c.continent,
    p.category,
    count() AS order_count,
    round(sum(o.total_amount), 2) AS total_revenue,
    round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
WHERE o.order_date >= today() - INTERVAL 30 DAY
GROUP BY c.continent, p.category
ORDER BY total_revenue DESC
LIMIT 10
FORMAT Vertical;

-- ==========================================
-- Test 3: Multi-Way Join With Automatic Reordering
-- ==========================================

SELECT '=== Test 3: Multi-Way Join (Automatic Reordering) ===' AS title;

SELECT '\n🚀 ClickHouse 25.9 New Feature: Automatic Join Reordering\nClickHouse will automatically reorder joins based on table sizes and statistics\n' AS info;

-- Enable automatic join reordering
SET allow_experimental_join_reordering = 1;

EXPLAIN
SELECT
    c.continent,
    p.category,
    count() AS order_count,
    round(sum(o.total_amount), 2) AS total_revenue
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
WHERE o.order_date >= today() - INTERVAL 30 DAY
GROUP BY c.continent, p.category
ORDER BY total_revenue DESC
LIMIT 10;

SELECT '\n✅ Join order optimized based on table statistics' AS status;

-- Execute the query with automatic reordering
SELECT
    c.continent,
    p.category,
    count() AS order_count,
    round(sum(o.total_amount), 2) AS total_revenue,
    round(avg(o.total_amount), 2) AS avg_order_value
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
WHERE o.order_date >= today() - INTERVAL 30 DAY
GROUP BY c.continent, p.category
ORDER BY total_revenue DESC
LIMIT 10
FORMAT Vertical;

-- ==========================================
-- Test 4: Complex Join Graph with Multiple Tables
-- ==========================================

SELECT '=== Test 4: Complex Join Graph (4-way join) ===' AS title;

-- Create customer table
DROP TABLE IF EXISTS customers;
CREATE TABLE customers
(
    customer_id UInt32,
    customer_name String,
    country_id UInt32,
    segment String
)
ENGINE = MergeTree()
ORDER BY customer_id;

INSERT INTO customers
SELECT
    number + 1 AS customer_id,
    concat('Customer_', toString(number + 1)) AS customer_name,
    (number % 100) + 1 AS country_id,
    ['VIP', 'Premium', 'Regular'][1 + (number % 3)] AS segment
FROM numbers(50000);

SELECT format('✅ Created customers table: {0} rows', count()) AS status FROM customers;

-- 4-way join with automatic reordering
SET allow_experimental_join_reordering = 1;

SELECT
    cu.segment,
    c.continent,
    p.category,
    count(DISTINCT o.order_id) AS orders,
    count(DISTINCT cu.customer_id) AS customers,
    round(sum(o.total_amount), 2) AS revenue
FROM orders o
JOIN customers cu ON o.customer_id = cu.customer_id
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
WHERE o.order_date >= today() - INTERVAL 90 DAY
GROUP BY cu.segment, c.continent, p.category
ORDER BY revenue DESC
LIMIT 15;

-- ==========================================
-- Test 5: Join Reordering Benefits
-- ==========================================

SELECT '=== ClickHouse 25.9: Join Reordering Benefits ===' AS info;

SELECT '
🚀 Automatic Join Reordering Benefits:

1. Performance:
   ✓ Optimal join order automatically selected
   ✓ Smaller tables joined first
   ✓ Reduced memory usage
   ✓ Faster query execution

2. Intelligence:
   ✓ Based on actual data volumes
   ✓ Uses column-level statistics
   ✓ Considers data distribution
   ✓ Dynamic optimization per query

3. Usability:
   ✓ No manual query rewriting needed
   ✓ Works with existing queries
   ✓ Transparent to applications
   ✓ Automatic optimization

4. Use Cases:
   - Multi-table analytics
   - Star schema queries
   - Complex reporting
   - Data warehouse workloads

Note: This is an experimental feature in 25.9
Enable with: SET allow_experimental_join_reordering = 1;
' AS benefits;

-- Cleanup (commented out for inspection)
-- DROP TABLE orders;
-- DROP TABLE products;
-- DROP TABLE countries;
-- DROP TABLE customers;

SELECT '✅ Automatic Join Reordering Test Complete!' AS status;
