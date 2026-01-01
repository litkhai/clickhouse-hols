-- ClickHouse 25.12 Feature: JOIN Order Optimization with DPSize Algorithm
-- Purpose: Test improved JOIN reordering with DPSize algorithm for better query performance
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- The DPSize algorithm in ClickHouse 25.12 provides more exhaustive search for
-- optimal JOIN order, leading to better query performance in multi-table joins.

SELECT '=== JOIN Order Optimization Overview ===' AS title;

-- Create sample tables for join optimization testing
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;

-- Customers table (large table)
CREATE TABLE customers
(
    customer_id UInt32,
    customer_name String,
    country String,
    registration_date Date
)
ENGINE = MergeTree()
ORDER BY customer_id;

-- Insert sample customers
INSERT INTO customers
SELECT
    number AS customer_id,
    concat('Customer_', toString(number)) AS customer_name,
    ['USA', 'UK', 'Germany', 'France', 'Japan'][number % 5 + 1] AS country,
    toDate('2020-01-01') + number % 1000 AS registration_date
FROM numbers(10000);

-- Orders table (large table)
CREATE TABLE orders
(
    order_id UInt32,
    customer_id UInt32,
    order_date Date,
    total_amount Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY (order_date, order_id);

-- Insert sample orders
INSERT INTO orders
SELECT
    number AS order_id,
    number % 10000 AS customer_id,
    toDate('2024-01-01') + (number % 365) AS order_date,
    round(rand() % 50000 / 100, 2) AS total_amount
FROM numbers(50000);

-- Order items table (very large table)
CREATE TABLE order_items
(
    item_id UInt64,
    order_id UInt32,
    product_id UInt32,
    quantity UInt16,
    price Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY (order_id, item_id);

-- Insert sample order items
INSERT INTO order_items
SELECT
    number AS item_id,
    number % 50000 AS order_id,
    number % 1000 AS product_id,
    (rand() % 10) + 1 AS quantity,
    round(rand() % 100000 / 100, 2) AS price
FROM numbers(150000);

-- Products table (medium table)
CREATE TABLE products
(
    product_id UInt32,
    product_name String,
    category_id UInt16,
    unit_price Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY product_id;

-- Insert sample products
INSERT INTO products
SELECT
    number AS product_id,
    concat('Product_', toString(number)) AS product_name,
    number % 50 AS category_id,
    round(rand() % 100000 / 100, 2) AS unit_price
FROM numbers(1000);

-- Categories table (small table)
CREATE TABLE categories
(
    category_id UInt16,
    category_name String,
    description String
)
ENGINE = MergeTree()
ORDER BY category_id;

-- Insert sample categories
INSERT INTO categories
SELECT
    number AS category_id,
    concat('Category_', toString(number)) AS category_name,
    concat('Description for category ', toString(number)) AS description
FROM numbers(50);

-- Query 1: View table sizes
SELECT '=== Table Sizes ===' AS title;
SELECT
    'customers' AS table_name,
    count() AS row_count,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed_size
FROM system.parts
WHERE database = currentDatabase() AND table = 'customers' AND active
UNION ALL
SELECT 'orders', count(*), '' FROM orders
UNION ALL
SELECT 'order_items', count(*), '' FROM order_items
UNION ALL
SELECT 'products', count(*), '' FROM products
UNION ALL
SELECT 'categories', count(*), '' FROM categories;

-- Query 2: Simple 2-table JOIN
SELECT '=== Simple 2-Table JOIN ===' AS title;
SELECT
    c.customer_name,
    count(o.order_id) AS order_count,
    sum(o.total_amount) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.country = 'USA'
GROUP BY c.customer_name
ORDER BY total_spent DESC
LIMIT 10;

-- Query 3: 3-table JOIN - Customer, Orders, Order Items
SELECT '=== 3-Table JOIN: Customer -> Orders -> Items ===' AS title;
SELECT
    c.customer_name,
    c.country,
    count(DISTINCT o.order_id) AS order_count,
    count(oi.item_id) AS item_count,
    sum(oi.quantity) AS total_quantity
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date >= '2024-01-01' AND o.order_date < '2024-02-01'
GROUP BY c.customer_name, c.country
ORDER BY item_count DESC
LIMIT 10;

-- Query 4: 4-table JOIN - Full analytics query
SELECT '=== 4-Table JOIN: Customer -> Orders -> Items -> Products ===' AS title;
SELECT
    c.country,
    p.product_name,
    count(DISTINCT o.order_id) AS order_count,
    sum(oi.quantity) AS total_quantity,
    sum(oi.quantity * oi.price) AS total_revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.order_date >= '2024-01-01'
GROUP BY c.country, p.product_name
ORDER BY total_revenue DESC
LIMIT 15;

-- Query 5: 5-table JOIN - Complete hierarchy
SELECT '=== 5-Table JOIN: Full Hierarchy with Categories ===' AS title;
SELECT
    cat.category_name,
    c.country,
    count(DISTINCT c.customer_id) AS customer_count,
    count(DISTINCT o.order_id) AS order_count,
    sum(oi.quantity) AS total_quantity,
    sum(oi.quantity * oi.price) AS total_revenue
FROM categories cat
JOIN products p ON cat.category_id = p.category_id
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2024-01-01'
GROUP BY cat.category_name, c.country
ORDER BY total_revenue DESC
LIMIT 20;

-- Query 6: Complex JOIN with multiple conditions
SELECT '=== Complex JOIN with Multiple Conditions ===' AS title;
SELECT
    c.customer_name,
    cat.category_name,
    count(DISTINCT o.order_id) AS orders,
    avg(oi.price) AS avg_price,
    sum(oi.quantity * oi.price) AS revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id AND o.order_date >= '2024-06-01'
JOIN order_items oi ON o.order_id = oi.order_id AND oi.quantity > 1
JOIN products p ON oi.product_id = p.product_id AND p.unit_price > 50
JOIN categories cat ON p.category_id = cat.category_id
WHERE c.country IN ('USA', 'UK', 'Germany')
GROUP BY c.customer_name, cat.category_name
HAVING revenue > 1000
ORDER BY revenue DESC
LIMIT 15;

-- Query 7: EXPLAIN query to see JOIN order
SELECT '=== EXPLAIN: Join Order Analysis ===' AS title;
EXPLAIN
SELECT
    cat.category_name,
    count(DISTINCT o.order_id) AS orders
FROM categories cat
JOIN products p ON cat.category_id = p.category_id
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE c.country = 'USA'
GROUP BY cat.category_name;

-- Query 8: Star schema JOIN pattern
SELECT '=== Star Schema Pattern ===' AS title;
WITH fact_table AS (
    SELECT
        order_id,
        customer_id,
        product_id,
        quantity,
        price,
        quantity * price AS revenue
    FROM order_items
)
SELECT
    c.country,
    cat.category_name,
    count(*) AS transaction_count,
    sum(f.revenue) AS total_revenue,
    avg(f.revenue) AS avg_revenue
FROM fact_table f
JOIN customers c ON f.customer_id = c.customer_id
JOIN products p ON f.product_id = p.product_id
JOIN categories cat ON p.category_id = cat.category_id
GROUP BY c.country, cat.category_name
ORDER BY total_revenue DESC
LIMIT 20;

-- Query 9: LEFT JOIN with optimization
SELECT '=== LEFT JOIN Optimization ===' AS title;
SELECT
    c.customer_name,
    c.country,
    coalesce(count(DISTINCT o.order_id), 0) AS order_count,
    coalesce(sum(o.total_amount), 0) AS total_spent
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
    AND o.order_date >= '2024-01-01'
WHERE c.registration_date >= '2024-01-01'
GROUP BY c.customer_name, c.country
ORDER BY order_count DESC
LIMIT 10;

-- Query 10: Subquery optimization with JOINs
SELECT '=== Subquery with JOIN Optimization ===' AS title;
WITH top_customers AS (
    SELECT
        customer_id,
        sum(total_amount) AS lifetime_value
    FROM orders
    GROUP BY customer_id
    HAVING lifetime_value > 10000
    ORDER BY lifetime_value DESC
    LIMIT 100
)
SELECT
    c.customer_name,
    c.country,
    tc.lifetime_value,
    count(DISTINCT cat.category_id) AS categories_purchased
FROM top_customers tc
JOIN customers c ON tc.customer_id = c.customer_id
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
JOIN categories cat ON p.category_id = cat.category_id
GROUP BY c.customer_name, c.country, tc.lifetime_value
ORDER BY tc.lifetime_value DESC
LIMIT 20;

-- Performance comparison settings
SELECT '=== JOIN Optimization Settings ===' AS info;
SELECT
    'join_algorithm' AS setting_name,
    'auto, hash, parallel_hash, direct, full_sorting_merge' AS possible_values,
    'Determines JOIN algorithm selection' AS description
UNION ALL
SELECT
    'max_rows_in_join',
    '0 (unlimited)',
    'Maximum rows in hash table for JOIN'
UNION ALL
SELECT
    'join_use_nulls',
    '0 or 1',
    'Use NULL for non-matching rows in LEFT/RIGHT JOIN'
UNION ALL
SELECT
    'join_default_strictness',
    'ALL, ANY',
    'Default JOIN strictness'
UNION ALL
SELECT
    'join_overflow_mode',
    'throw, break',
    'Behavior when JOIN size limit exceeded';

-- Benefits of JOIN Order Optimization
SELECT '=== JOIN Order Optimization Benefits ===' AS info;
SELECT
    'Automatic optimization of multi-table JOINs' AS benefit_1,
    'DPSize algorithm for exhaustive search' AS benefit_2,
    'Reduced query execution time' AS benefit_3,
    'Lower memory consumption' AS benefit_4,
    'Better handling of complex queries' AS benefit_5,
    'Transparent to query writers' AS benefit_6;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Complex analytics queries with multiple tables' AS use_case_1,
    'Star schema and snowflake schema queries' AS use_case_2,
    'E-commerce product and order analytics' AS use_case_3,
    'Multi-dimensional business intelligence' AS use_case_4,
    'Data warehouse reporting' AS use_case_5,
    'Ad-hoc analytical queries' AS use_case_6,
    'Dashboard and BI tool queries' AS use_case_7;

-- Best Practices
SELECT '=== JOIN Optimization Best Practices ===' AS info;
SELECT
    'Start with smallest table when possible' AS practice_1,
    'Use proper JOIN keys with good cardinality' AS practice_2,
    'Consider denormalization for frequent JOINs' AS practice_3,
    'Use appropriate indexes on JOIN keys' AS practice_4,
    'Filter data early in the query' AS practice_5,
    'Use EXPLAIN to understand execution plan' AS practice_6,
    'Monitor query performance metrics' AS practice_7;

-- Cleanup (commented out for inspection)
-- DROP TABLE categories;
-- DROP TABLE products;
-- DROP TABLE order_items;
-- DROP TABLE orders;
-- DROP TABLE customers;

SELECT '✅ JOIN Order Optimization Test Complete!' AS status;
