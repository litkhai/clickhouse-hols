-- ClickHouse 25.10 Feature: JOIN Improvements
-- Purpose: Test lazy materialization, filter push-down, and automatic condition derivation
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- Features tested:
-- 1. Lazy materialization during JOIN (memory/CPU optimization)
-- 2. Small filter built from one JOIN side used as "PREWHERE" in another
-- 3. Automatic derivation of conditions for left and right tables

-- Create tables for JOIN testing
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;

CREATE TABLE customers
(
    customer_id UInt32,
    customer_name String,
    country String,
    registration_date Date
)
ENGINE = MergeTree()
ORDER BY customer_id;

CREATE TABLE orders
(
    order_id UInt32,
    customer_id UInt32,
    product_id UInt32,
    order_date Date,
    quantity UInt32,
    total_amount Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY (customer_id, order_date);

CREATE TABLE products
(
    product_id UInt32,
    product_name String,
    category String,
    price Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY product_id;

-- Insert sample data
INSERT INTO customers VALUES
    (1, 'Alice Johnson', 'USA', '2024-01-15'),
    (2, 'Bob Smith', 'UK', '2024-02-20'),
    (3, 'Charlie Brown', 'USA', '2024-03-10'),
    (4, 'David Lee', 'Korea', '2024-04-05'),
    (5, 'Eve Wilson', 'UK', '2024-05-12'),
    (6, 'Frank Zhang', 'Korea', '2024-06-18'),
    (7, 'Grace Park', 'USA', '2024-07-22'),
    (8, 'Henry Kim', 'Korea', '2024-08-30');

INSERT INTO orders VALUES
    (101, 1, 1, '2024-06-01', 2, 39.98),
    (102, 1, 3, '2024-06-15', 1, 299.99),
    (103, 2, 2, '2024-06-10', 1, 149.99),
    (104, 3, 1, '2024-07-01', 5, 99.95),
    (105, 3, 4, '2024-07-05', 2, 59.98),
    (106, 4, 2, '2024-07-20', 1, 149.99),
    (107, 5, 3, '2024-08-01', 1, 299.99),
    (108, 6, 1, '2024-08-15', 3, 59.97),
    (109, 7, 4, '2024-09-01', 4, 119.96),
    (110, 8, 2, '2024-09-10', 2, 299.98);

INSERT INTO products VALUES
    (1, 'Wireless Mouse', 'Electronics', 19.99),
    (2, 'Mechanical Keyboard', 'Electronics', 149.99),
    (3, 'USB-C Hub', 'Electronics', 299.99),
    (4, 'Phone Stand', 'Accessories', 29.99);

-- Query 1: Basic JOIN to verify data
SELECT '=== Basic JOIN - Verify Data ===' AS title;
SELECT
    c.customer_name,
    c.country,
    o.order_id,
    p.product_name,
    o.quantity,
    o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id = p.product_id
ORDER BY o.order_date
LIMIT 5;

-- Query 2: Lazy Materialization Demo
-- When a block multiplies many times during JOIN, it's done lazily
SELECT '=== Lazy Materialization Test ===' AS title;
SELECT
    c.country,
    count() AS order_count,
    sum(o.total_amount) AS total_revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.country
ORDER BY total_revenue DESC;

-- Query 3: Filter Push-Down (PREWHERE-like optimization)
-- Small filter from one side used to optimize reading from another
SELECT '=== Filter Push-Down Demo ===' AS title;
SELECT
    c.customer_name,
    c.country,
    p.product_name,
    o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id = p.product_id
WHERE c.country = 'USA'  -- This filter can be pushed down
  AND p.category = 'Electronics'
ORDER BY o.total_amount DESC;

-- Query 4: Automatic Condition Derivation
-- Complex WHERE clauses with automatic push-down to both tables
SELECT '=== Automatic Condition Derivation ===' AS title;
SELECT
    c.customer_name,
    c.country,
    o.order_date,
    p.product_name,
    o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id = p.product_id
WHERE c.registration_date >= '2024-04-01'
  AND o.order_date >= '2024-07-01'
  AND p.price > 50
ORDER BY o.order_date;

-- Query 5: Complex JOIN with aggregation
-- Tests lazy materialization with multiple aggregations
SELECT '=== Complex JOIN with Aggregation ===' AS title;
SELECT
    c.country,
    p.category,
    count(DISTINCT c.customer_id) AS customer_count,
    count(o.order_id) AS order_count,
    sum(o.quantity) AS total_quantity,
    sum(o.total_amount) AS total_revenue,
    avg(o.total_amount) AS avg_order_value
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id = p.product_id
GROUP BY c.country, p.category
ORDER BY total_revenue DESC;

-- Query 6: Multiple JOIN conditions with derived predicates
SELECT '=== Multiple JOIN Conditions ===' AS title;
SELECT
    c.customer_name,
    c.country,
    count(o.order_id) AS num_orders,
    sum(o.total_amount) AS total_spent,
    arrayStringConcat(groupArray(p.product_name), ', ') AS products_purchased
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
    AND o.order_date >= '2024-06-01'
LEFT JOIN products p ON o.product_id = p.product_id
GROUP BY c.customer_id, c.customer_name, c.country
HAVING num_orders > 0
ORDER BY total_spent DESC;

-- Query 7: Subquery JOIN with optimization
SELECT '=== Subquery JOIN Optimization ===' AS title;
WITH top_customers AS (
    SELECT
        customer_id,
        sum(total_amount) AS total
    FROM orders
    GROUP BY customer_id
    HAVING total > 100
)
SELECT
    c.customer_name,
    c.country,
    tc.total AS total_spent,
    count(o.order_id) AS order_count
FROM top_customers tc
JOIN customers c ON tc.customer_id = c.customer_id
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_name, c.country, tc.total
ORDER BY tc.total DESC;

-- Query 8: EXPLAIN to see query optimization
SELECT '=== Query Execution Plan ===' AS title;
EXPLAIN
SELECT
    c.customer_name,
    p.product_name,
    o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN products p ON o.product_id = p.product_id
WHERE c.country = 'USA'
  AND p.category = 'Electronics';

-- Performance Benefits Summary
SELECT '=== JOIN Improvements Benefits ===' AS info;
SELECT
    'Lazy materialization reduces memory usage' AS benefit_1,
    'Filter push-down improves read performance' AS benefit_2,
    'Automatic condition derivation optimizes complex queries' AS benefit_3,
    'Better CPU utilization with lazy block multiplication' AS benefit_4;

-- Cleanup
-- DROP TABLE customers;
-- DROP TABLE orders;
-- DROP TABLE products;

SELECT '✅ JOIN Improvements Test Complete!' AS status;
