-- ClickHouse 25.7 Feature: JOIN Performance Improvements
-- Purpose: Test the improved JOIN operations (up to 1.8x speedups)
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-07

-- Drop tables if exist
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS products;

-- Create customers table
CREATE TABLE customers
(
    customer_id UInt32,
    customer_name String,
    email String,
    country String,
    signup_date Date,
    customer_segment String
)
ENGINE = MergeTree()
ORDER BY customer_id;

-- Insert customer data (1 million customers)
INSERT INTO customers
SELECT
    number as customer_id,
    concat('Customer-', toString(number)) as customer_name,
    concat('user', toString(number), '@example.com') as email,
    ['US', 'UK', 'DE', 'FR', 'JP', 'CN', 'IN', 'BR', 'AU', 'CA'][1 + (number % 10)] as country,
    toDate('2020-01-01') + toIntervalDay(number % 1825) as signup_date,
    ['Premium', 'Standard', 'Basic'][1 + (number % 3)] as customer_segment
FROM numbers(1000000);

-- Create orders table
CREATE TABLE orders
(
    order_id UInt64,
    customer_id UInt32,
    order_date DateTime,
    total_amount Decimal(10, 2),
    status String,
    shipping_country String
)
ENGINE = MergeTree()
ORDER BY (order_date, customer_id)
PARTITION BY toYYYYMM(order_date);

-- Insert order data (5 million orders)
INSERT INTO orders
SELECT
    number as order_id,
    (number % 1000000) as customer_id,
    toDateTime('2024-01-01 00:00:00') + toIntervalSecond(number % 31536000) as order_date,
    round(10 + (number % 1000), 2) as total_amount,
    ['pending', 'completed', 'shipped', 'cancelled'][1 + (number % 4)] as status,
    ['US', 'UK', 'DE', 'FR', 'JP', 'CN', 'IN', 'BR', 'AU', 'CA'][1 + (number % 10)] as shipping_country
FROM numbers(5000000);

-- Create products table
CREATE TABLE products
(
    product_id UInt32,
    product_name String,
    category String,
    price Decimal(10, 2),
    supplier String
)
ENGINE = MergeTree()
ORDER BY product_id;

-- Insert product data (100,000 products)
INSERT INTO products
SELECT
    number as product_id,
    concat('Product-', toString(number)) as product_name,
    ['Electronics', 'Clothing', 'Books', 'Home', 'Sports', 'Toys'][1 + (number % 6)] as category,
    round(5 + (number % 995), 2) as price,
    concat('Supplier-', toString(number % 1000)) as supplier
FROM numbers(100000);

-- Create order_items table
CREATE TABLE order_items
(
    order_id UInt64,
    product_id UInt32,
    quantity UInt16,
    unit_price Decimal(10, 2),
    discount Decimal(5, 2)
)
ENGINE = MergeTree()
ORDER BY (order_id, product_id);

-- Insert order items data (20 million items)
INSERT INTO order_items
SELECT
    (number % 5000000) as order_id,
    (number % 100000) as product_id,
    1 + (number % 5) as quantity,
    round(10 + (number % 500), 2) as unit_price,
    round((number % 30) * 0.1, 2) as discount
FROM numbers(20000000);

SELECT '=== Test Data Created ===' AS title;
SELECT
    (SELECT count() FROM customers) as customers,
    (SELECT count() FROM orders) as orders,
    (SELECT count() FROM products) as products,
    (SELECT count() FROM order_items) as order_items;

-- Test 1: Simple INNER JOIN - Optimized in 25.7 (up to 1.8x faster)
SELECT '=== Test 1: INNER JOIN - Customers and Orders ===' AS title;
SELECT
    c.customer_segment,
    count(DISTINCT c.customer_id) as customers,
    count(o.order_id) as total_orders,
    round(avg(o.total_amount), 2) as avg_order_value,
    round(sum(o.total_amount), 2) as total_revenue
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_date >= '2024-01-01'
  AND o.status = 'completed'
GROUP BY c.customer_segment
ORDER BY total_revenue DESC;

-- Test 2: LEFT JOIN with aggregation
SELECT '=== Test 2: LEFT JOIN - All Customers with Order Stats ===' AS title;
SELECT
    c.country,
    count(DISTINCT c.customer_id) as total_customers,
    count(o.order_id) as total_orders,
    round(avg(o.total_amount), 2) as avg_order_value,
    countIf(o.order_id IS NULL) as customers_no_orders
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status = 'completed'
GROUP BY c.country
ORDER BY total_orders DESC
LIMIT 10;

-- Test 3: Multi-table JOIN (3 tables) - Performance improvement
SELECT '=== Test 3: Multi-Table JOIN - Orders, Items, Products ===' AS title;
SELECT
    p.category,
    count(DISTINCT o.order_id) as orders,
    sum(oi.quantity) as total_quantity_sold,
    round(sum(oi.quantity * oi.unit_price * (1 - oi.discount / 100)), 2) as total_revenue,
    round(avg(oi.unit_price), 2) as avg_unit_price
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
WHERE o.order_date >= '2024-06-01'
  AND o.status IN ('completed', 'shipped')
GROUP BY p.category
ORDER BY total_revenue DESC;

-- Test 4: Complex JOIN with WHERE and GROUP BY
SELECT '=== Test 4: Customer Segment Analysis with Multi-JOIN ===' AS title;
SELECT
    c.customer_segment,
    c.country,
    count(DISTINCT c.customer_id) as customers,
    count(DISTINCT o.order_id) as orders,
    sum(oi.quantity) as items_sold,
    round(sum(oi.quantity * oi.unit_price), 2) as gross_revenue,
    round(sum(oi.quantity * oi.unit_price * oi.discount / 100), 2) as total_discounts,
    round(sum(oi.quantity * oi.unit_price * (1 - oi.discount / 100)), 2) as net_revenue
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date >= '2024-01-01'
  AND o.status = 'completed'
GROUP BY c.customer_segment, c.country
HAVING count(DISTINCT o.order_id) > 100
ORDER BY net_revenue DESC
LIMIT 20;

-- Test 5: JOIN with subquery (optimized)
SELECT '=== Test 5: JOIN with Subquery - High Value Customers ===' AS title;
WITH high_value_customers AS (
    SELECT
        customer_id,
        sum(total_amount) as lifetime_value
    FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id
    HAVING sum(total_amount) > 50000
)
SELECT
    c.customer_segment,
    c.country,
    count(DISTINCT c.customer_id) as high_value_customers,
    round(avg(hvc.lifetime_value), 2) as avg_lifetime_value,
    round(sum(hvc.lifetime_value), 2) as total_lifetime_value
FROM customers c
INNER JOIN high_value_customers hvc ON c.customer_id = hvc.customer_id
GROUP BY c.customer_segment, c.country
ORDER BY total_lifetime_value DESC;

-- Test 6: Time-based JOIN analysis
SELECT '=== Test 6: Monthly Revenue Trend with JOINs ===' AS title;
SELECT
    toStartOfMonth(o.order_date) as month,
    count(DISTINCT c.customer_id) as active_customers,
    count(DISTINCT o.order_id) as orders,
    sum(oi.quantity) as items_sold,
    round(sum(oi.quantity * oi.unit_price * (1 - oi.discount / 100)), 2) as revenue
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date >= '2024-01-01'
  AND o.status = 'completed'
GROUP BY month
ORDER BY month;

-- Test 7: JOIN with multiple conditions
SELECT '=== Test 7: Cross-Border Orders Analysis ===' AS title;
SELECT
    c.country as customer_country,
    o.shipping_country,
    count(DISTINCT o.order_id) as orders,
    round(avg(o.total_amount), 2) as avg_order_value,
    CASE
        WHEN c.country = o.shipping_country THEN 'Domestic'
        ELSE 'International'
    END as order_type
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_date >= '2024-01-01'
  AND o.status IN ('completed', 'shipped')
GROUP BY customer_country, shipping_country, order_type
HAVING orders > 1000
ORDER BY orders DESC
LIMIT 20;

-- Test 8: Product-level JOIN analysis
SELECT '=== Test 8: Top Products by Customer Segment ===' AS title;
SELECT
    c.customer_segment,
    p.product_name,
    p.category,
    count(DISTINCT o.order_id) as orders,
    sum(oi.quantity) as quantity_sold,
    round(sum(oi.quantity * oi.unit_price * (1 - oi.discount / 100)), 2) as revenue
FROM customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
WHERE o.order_date >= '2024-01-01'
  AND o.status = 'completed'
GROUP BY c.customer_segment, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 30;

-- Test 9: Self-JOIN scenario - Customer referral analysis
DROP TABLE IF EXISTS customer_referrals;

CREATE TABLE customer_referrals
(
    customer_id UInt32,
    referred_by_customer_id UInt32,
    referral_date Date
)
ENGINE = MergeTree()
ORDER BY customer_id;

INSERT INTO customer_referrals
SELECT
    number as customer_id,
    (number - 1 - (number % 10)) as referred_by_customer_id,
    toDate('2024-01-01') + toIntervalDay(number % 365) as referral_date
FROM numbers(100000)
WHERE number > 0 AND (number % 10) != 0;

SELECT '=== Test 9: Self-JOIN - Referral Network ===' AS title;
SELECT
    c1.customer_segment as referrer_segment,
    c2.customer_segment as referred_segment,
    count(DISTINCT cr.customer_id) as referrals,
    round(avg(dateDiff('day', c1.signup_date, cr.referral_date)), 2) as avg_days_to_refer
FROM customer_referrals cr
INNER JOIN customers c1 ON cr.referred_by_customer_id = c1.customer_id
INNER JOIN customers c2 ON cr.customer_id = c2.customer_id
GROUP BY referrer_segment, referred_segment
ORDER BY referrals DESC;

-- Test 10: Complex analytical query with multiple JOINs and window functions
SELECT '=== Test 10: Advanced Analytics - Running Totals ===' AS title;
SELECT
    month,
    category,
    revenue,
    sum(revenue) OVER (PARTITION BY category ORDER BY month) as running_total,
    round(revenue * 100.0 / sum(revenue) OVER (PARTITION BY month), 2) as pct_of_month
FROM (
    SELECT
        toStartOfMonth(o.order_date) as month,
        p.category,
        round(sum(oi.quantity * oi.unit_price * (1 - oi.discount / 100)), 2) as revenue
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    INNER JOIN products p ON oi.product_id = p.product_id
    WHERE o.order_date >= '2024-01-01'
      AND o.order_date < '2024-04-01'
      AND o.status = 'completed'
    GROUP BY month, category
) t
ORDER BY category, month
LIMIT 50;

-- Test 11: JOIN performance with different JOIN algorithms
SELECT '=== Test 11: Customer Retention Analysis ===' AS title;
WITH first_orders AS (
    SELECT
        customer_id,
        min(order_date) as first_order_date,
        min(order_id) as first_order_id
    FROM orders
    WHERE status = 'completed'
    GROUP BY customer_id
),
repeat_customers AS (
    SELECT
        o.customer_id,
        count(DISTINCT o.order_id) as total_orders,
        sum(o.total_amount) as lifetime_value
    FROM orders o
    INNER JOIN first_orders fo ON o.customer_id = fo.customer_id
    WHERE o.status = 'completed'
      AND o.order_date > fo.first_order_date
    GROUP BY o.customer_id
)
SELECT
    c.customer_segment,
    count(DISTINCT c.customer_id) as total_customers,
    count(DISTINCT rc.customer_id) as repeat_customers,
    round(count(DISTINCT rc.customer_id) * 100.0 / count(DISTINCT c.customer_id), 2) as retention_rate,
    round(avg(rc.total_orders), 2) as avg_repeat_orders,
    round(avg(rc.lifetime_value), 2) as avg_lifetime_value
FROM customers c
LEFT JOIN repeat_customers rc ON c.customer_id = rc.customer_id
GROUP BY c.customer_segment
ORDER BY retention_rate DESC;

-- Performance insights
SELECT '=== ClickHouse 25.7 JOIN Performance Benefits ===' AS info;
SELECT
    'Up to 1.8x faster JOIN operations' AS benefit_1,
    'Optimized hash table building and probing' AS benefit_2,
    'Better memory efficiency in large JOINs' AS benefit_3,
    'Improved performance for multi-table JOINs' AS benefit_4,
    'Enhanced query planning for complex JOIN scenarios' AS benefit_5;

-- Use cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'E-commerce analytics with customer and order analysis' AS use_case_1,
    'Multi-dimensional business intelligence dashboards' AS use_case_2,
    'Customer segmentation and cohort analysis' AS use_case_3,
    'Supply chain and inventory management reporting' AS use_case_4,
    'Financial reporting with transaction reconciliation' AS use_case_5,
    'Marketing attribution and campaign performance' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE customer_referrals;
-- DROP TABLE order_items;
-- DROP TABLE products;
-- DROP TABLE orders;
-- DROP TABLE customers;

SELECT '✅ JOIN Performance Test Complete!' AS status;
