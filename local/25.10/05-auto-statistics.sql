-- ClickHouse 25.10 Feature: Auto Statistics
-- Purpose: Test automatic statistics collection for query optimization
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- Features:
-- 1. Table-level setting for enabling statistics on all columns automatically
-- 2. Support for minmax, uniq, and countmin statistics types
-- 3. Statistics used for automatic JOIN reordering

-- Create tables with auto statistics enabled
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_products;
DROP TABLE IF EXISTS dim_customers;

-- Fact table with auto statistics
CREATE TABLE fact_sales
(
    sale_id UInt64,
    product_id UInt32,
    customer_id UInt32,
    sale_date Date,
    quantity UInt32,
    unit_price Decimal(10, 2),
    total_amount Decimal(12, 2),
    region String
)
ENGINE = MergeTree()
ORDER BY (sale_date, sale_id)
SETTINGS
    -- Enable auto statistics (new in 25.10)
    auto_collect_statistics = 1,
    statistics_accurate_sample_size = 100000;

-- Dimension table: Products
CREATE TABLE dim_products
(
    product_id UInt32,
    product_name String,
    category String,
    brand String,
    cost Decimal(10, 2),
    price Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY product_id
SETTINGS
    auto_collect_statistics = 1;

-- Dimension table: Customers
CREATE TABLE dim_customers
(
    customer_id UInt32,
    customer_name String,
    customer_type String,
    city String,
    country String,
    registration_date Date
)
ENGINE = MergeTree()
ORDER BY customer_id
SETTINGS
    auto_collect_statistics = 1;

-- Insert sample data into products
INSERT INTO dim_products VALUES
    (1, 'Laptop Pro 15', 'Electronics', 'TechBrand', 800, 1299.99),
    (2, 'Wireless Mouse', 'Electronics', 'TechBrand', 10, 29.99),
    (3, 'USB-C Cable', 'Accessories', 'ConnectCo', 2, 9.99),
    (4, 'Desk Chair', 'Furniture', 'OfficeMax', 120, 249.99),
    (5, 'Monitor 27"', 'Electronics', 'ViewTech', 200, 399.99),
    (6, 'Keyboard RGB', 'Electronics', 'TechBrand', 40, 89.99),
    (7, 'Desk Lamp', 'Accessories', 'LightCo', 15, 39.99),
    (8, 'Webcam HD', 'Electronics', 'ViewTech', 50, 119.99);

-- Insert sample data into customers
INSERT INTO dim_customers VALUES
    (101, 'Alice Johnson', 'Premium', 'New York', 'USA', '2023-01-15'),
    (102, 'Bob Smith', 'Standard', 'London', 'UK', '2023-03-20'),
    (103, 'Charlie Brown', 'Premium', 'Toronto', 'Canada', '2023-05-10'),
    (104, 'Diana Prince', 'Standard', 'Sydney', 'Australia', '2023-06-25'),
    (105, 'Eve Wilson', 'Premium', 'Tokyo', 'Japan', '2023-08-12'),
    (106, 'Frank Zhang', 'Standard', 'Seoul', 'Korea', '2023-09-30'),
    (107, 'Grace Lee', 'Premium', 'Singapore', 'Singapore', '2023-11-05'),
    (108, 'Henry Kim', 'Standard', 'Berlin', 'Germany', '2023-12-18');

-- Insert sample sales data
INSERT INTO fact_sales VALUES
    (1001, 1, 101, '2024-09-01', 1, 1299.99, 1299.99, 'North America'),
    (1002, 2, 102, '2024-09-02', 2, 29.99, 59.98, 'Europe'),
    (1003, 3, 103, '2024-09-03', 5, 9.99, 49.95, 'North America'),
    (1004, 4, 104, '2024-09-04', 1, 249.99, 249.99, 'Asia Pacific'),
    (1005, 5, 105, '2024-09-05', 1, 399.99, 399.99, 'Asia'),
    (1006, 6, 106, '2024-09-06', 1, 89.99, 89.99, 'Asia'),
    (1007, 7, 107, '2024-09-07', 2, 39.99, 79.98, 'Asia Pacific'),
    (1008, 1, 108, '2024-09-08', 1, 1299.99, 1299.99, 'Europe'),
    (1009, 2, 101, '2024-09-09', 3, 29.99, 89.97, 'North America'),
    (1010, 8, 102, '2024-09-10', 1, 119.99, 119.99, 'Europe'),
    (1011, 3, 103, '2024-09-11', 10, 9.99, 99.90, 'North America'),
    (1012, 4, 105, '2024-09-12', 2, 249.99, 499.98, 'Asia'),
    (1013, 5, 106, '2024-09-13', 1, 399.99, 399.99, 'Asia'),
    (1014, 6, 107, '2024-09-14', 2, 89.99, 179.98, 'Asia Pacific'),
    (1015, 1, 101, '2024-09-15', 1, 1299.99, 1299.99, 'North America');

-- Query 1: Check table statistics settings
SELECT '=== Table Statistics Settings ===' AS title;
SELECT
    table,
    name AS setting_name,
    value
FROM system.settings
WHERE name LIKE '%statistic%'
LIMIT 10;

-- Query 2: View collected statistics
SELECT '=== System Statistics ===' AS title;
SELECT
    database,
    table,
    column,
    type,
    rows_count,
    data_compressed_bytes,
    data_uncompressed_bytes
FROM system.statistics
WHERE database = currentDatabase()
ORDER BY table, column;

-- Query 3: Basic query with statistics
SELECT '=== Sales by Product Category ===' AS title;
SELECT
    p.category,
    count() AS num_sales,
    sum(s.quantity) AS total_quantity,
    sum(s.total_amount) AS total_revenue,
    avg(s.total_amount) AS avg_sale_amount
FROM fact_sales s
JOIN dim_products p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY total_revenue DESC;

-- Query 4: JOIN with automatic reordering
-- Statistics help optimizer choose best JOIN order
SELECT '=== Customer Sales Analysis ===' AS title;
SELECT
    c.customer_name,
    c.customer_type,
    c.country,
    count(s.sale_id) AS num_purchases,
    sum(s.total_amount) AS total_spent,
    avg(s.total_amount) AS avg_purchase
FROM fact_sales s
JOIN dim_customers c ON s.customer_id = c.customer_id
JOIN dim_products p ON s.product_id = p.product_id
WHERE p.category = 'Electronics'
GROUP BY c.customer_id, c.customer_name, c.customer_type, c.country
HAVING num_purchases > 0
ORDER BY total_spent DESC;

-- Query 5: Complex query with multiple JOINs
-- Statistics enable optimal JOIN reordering
SELECT '=== Regional Product Performance ===' AS title;
SELECT
    s.region,
    p.category,
    p.brand,
    count(DISTINCT s.customer_id) AS unique_customers,
    count(s.sale_id) AS num_sales,
    sum(s.quantity) AS total_units,
    sum(s.total_amount) AS revenue
FROM fact_sales s
JOIN dim_products p ON s.product_id = p.product_id
JOIN dim_customers c ON s.customer_id = c.customer_id
WHERE s.sale_date >= '2024-09-01'
GROUP BY s.region, p.category, p.brand
ORDER BY revenue DESC;

-- Query 6: EXPLAIN to see query plan with statistics
SELECT '=== Query Plan with Statistics ===' AS title;
EXPLAIN
SELECT
    p.product_name,
    c.customer_name,
    s.total_amount
FROM fact_sales s
JOIN dim_products p ON s.product_id = p.product_id
JOIN dim_customers c ON s.customer_id = c.customer_id
WHERE s.sale_date >= '2024-09-01'
  AND p.category = 'Electronics'
  AND c.customer_type = 'Premium'
ORDER BY s.total_amount DESC;

-- Query 7: Statistics-driven aggregation
SELECT '=== Top Products by Revenue ===' AS title;
SELECT
    p.product_name,
    p.category,
    p.brand,
    count() AS num_sales,
    sum(s.quantity) AS total_units_sold,
    sum(s.total_amount) AS total_revenue,
    sum(s.total_amount) - sum(s.quantity * p.cost) AS profit
FROM fact_sales s
JOIN dim_products p ON s.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category, p.brand
ORDER BY total_revenue DESC
LIMIT 5;

-- Query 8: Premium customers analysis
SELECT '=== Premium vs Standard Customers ===' AS title;
SELECT
    c.customer_type,
    count(DISTINCT c.customer_id) AS num_customers,
    count(s.sale_id) AS total_purchases,
    sum(s.total_amount) AS total_revenue,
    avg(s.total_amount) AS avg_purchase_value,
    sum(s.total_amount) / count(DISTINCT c.customer_id) AS revenue_per_customer
FROM dim_customers c
LEFT JOIN fact_sales s ON c.customer_id = s.customer_id
GROUP BY c.customer_type
ORDER BY revenue_per_customer DESC;

-- Query 9: Check statistics information
SELECT '=== Statistics Metadata ===' AS title;
SELECT
    table,
    column,
    type,
    rows_count,
    formatReadableSize(data_compressed_bytes) AS compressed_size,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed_size,
    round(data_uncompressed_bytes / data_compressed_bytes, 2) AS compression_ratio
FROM system.statistics
WHERE database = currentDatabase()
  AND table IN ('fact_sales', 'dim_products', 'dim_customers')
ORDER BY table, column;

-- Benefits of Auto Statistics
SELECT '=== Auto Statistics Benefits ===' AS info;
SELECT
    'Automatic collection without manual configuration' AS benefit_1,
    'Enables intelligent JOIN reordering' AS benefit_2,
    'Improves query performance through better optimization' AS benefit_3,
    'Supports minmax, uniq, and countmin statistics types' AS benefit_4,
    'Table-level setting for easy enablement' AS benefit_5;

-- Cleanup
-- DROP TABLE fact_sales;
-- DROP TABLE dim_products;
-- DROP TABLE dim_customers;

SELECT '✅ Auto Statistics Test Complete!' AS status;
