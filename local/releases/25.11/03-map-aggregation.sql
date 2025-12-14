-- ClickHouse 25.11 Feature: Map Aggregation Support
-- Purpose: Test sumMap aggregate function for Map type aggregation
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Drop table if exists
DROP TABLE IF EXISTS user_metrics;

-- Create a table with Map type columns for semi-structured data
CREATE TABLE user_metrics
(
    user_id UInt32,
    metric_date Date,
    daily_stats Map(String, UInt64),  -- Map for various count metrics
    revenue_by_product Map(String, Decimal(10, 2)),  -- Map for revenue data
    performance_scores Map(String, Float32)  -- Map for performance metrics
)
ENGINE = MergeTree()
ORDER BY (user_id, metric_date);

-- Insert sample data with Map types
INSERT INTO user_metrics VALUES
    (1, '2025-01-01',
     map('page_views', 150, 'clicks', 45, 'sessions', 12),
     map('electronics', 1200.50, 'books', 89.99, 'clothing', 250.00),
     map('engagement', 85.5, 'satisfaction', 92.3, 'retention', 78.9)),
    (1, '2025-01-02',
     map('page_views', 180, 'clicks', 52, 'sessions', 15),
     map('electronics', 1500.00, 'books', 120.50, 'clothing', 300.00),
     map('engagement', 88.2, 'satisfaction', 94.1, 'retention', 81.2)),
    (2, '2025-01-01',
     map('page_views', 95, 'clicks', 28, 'sessions', 8),
     map('electronics', 800.00, 'books', 45.99, 'clothing', 150.00),
     map('engagement', 72.5, 'satisfaction', 85.6, 'retention', 65.3)),
    (2, '2025-01-02',
     map('page_views', 110, 'clicks', 35, 'sessions', 10),
     map('electronics', 950.00, 'books', 65.50, 'clothing', 200.00),
     map('engagement', 75.8, 'satisfaction', 87.9, 'retention', 68.7)),
    (3, '2025-01-01',
     map('page_views', 200, 'clicks', 60, 'sessions', 18),
     map('electronics', 2000.00, 'books', 150.00, 'clothing', 450.00),
     map('engagement', 95.3, 'satisfaction', 98.5, 'retention', 92.1));

-- Query 1: View all user metrics
SELECT '=== All User Metrics ===' AS title;
SELECT
    user_id,
    metric_date,
    daily_stats,
    revenue_by_product,
    performance_scores
FROM user_metrics
ORDER BY user_id, metric_date;

-- Query 2: NEW FEATURE - sumMap aggregation on Map
SELECT '=== sumMap Aggregation on Map ===' AS title;
SELECT
    user_id,
    sumMap(daily_stats) AS total_stats,
    sumMap(revenue_by_product) AS total_revenue
FROM user_metrics
GROUP BY user_id
ORDER BY user_id;

-- Query 3: sumMap for performance scores
SELECT '=== sumMap on Performance Scores ===' AS title;
SELECT
    user_id,
    sumMap(performance_scores) AS total_scores
FROM user_metrics
GROUP BY user_id
ORDER BY user_id;

-- Query 4: Global aggregation with sumMap
SELECT '=== Global sumMap Aggregation ===' AS title;
SELECT
    sumMap(daily_stats) AS global_total_stats,
    sumMap(revenue_by_product) AS global_total_revenue,
    count() AS days_recorded
FROM user_metrics;

-- Real-world use case: E-commerce analytics with semi-structured data
DROP TABLE IF EXISTS product_analytics;

CREATE TABLE product_analytics
(
    product_id UInt32,
    analysis_date Date,
    sales_by_region Map(String, UInt32),  -- Sales count by region
    revenue_by_channel Map(String, Decimal(12, 2)),  -- Revenue by sales channel
    conversion_rates Map(String, Float64),  -- Conversion rates by source
    inventory_levels Map(String, UInt32)  -- Inventory by warehouse
)
ENGINE = MergeTree()
ORDER BY (product_id, analysis_date);

-- Insert e-commerce analytics data
INSERT INTO product_analytics VALUES
    (101, '2025-01-01',
     map('US', 150, 'EU', 89, 'ASIA', 125, 'OTHER', 45),
     map('online', 45000.00, 'retail', 28000.00, 'partner', 12000.00),
     map('organic', 0.045, 'paid', 0.038, 'social', 0.025, 'email', 0.062),
     map('warehouse_a', 500, 'warehouse_b', 350, 'warehouse_c', 200)),
    (101, '2025-01-02',
     map('US', 165, 'EU', 95, 'ASIA', 140, 'OTHER', 50),
     map('online', 48000.00, 'retail', 31000.00, 'partner', 15000.00),
     map('organic', 0.048, 'paid', 0.041, 'social', 0.028, 'email', 0.065),
     map('warehouse_a', 450, 'warehouse_b', 320, 'warehouse_c', 180)),
    (102, '2025-01-01',
     map('US', 200, 'EU', 120, 'ASIA', 180, 'OTHER', 60),
     map('online', 60000.00, 'retail', 42000.00, 'partner', 18000.00),
     map('organic', 0.052, 'paid', 0.045, 'social', 0.031, 'email', 0.071),
     map('warehouse_a', 800, 'warehouse_b', 600, 'warehouse_c', 400)),
    (102, '2025-01-02',
     map('US', 210, 'EU', 130, 'ASIA', 195, 'OTHER', 65),
     map('online', 63000.00, 'retail', 45000.00, 'partner', 20000.00),
     map('organic', 0.055, 'paid', 0.048, 'social', 0.034, 'email', 0.075),
     map('warehouse_a', 750, 'warehouse_b', 550, 'warehouse_c', 350));

-- Query 5: Total sales by region across all products
SELECT '=== Total Sales by Region (sumMap) ===' AS title;
SELECT
    product_id,
    sumMap(sales_by_region) AS total_sales_by_region
FROM product_analytics
GROUP BY product_id
ORDER BY product_id;

-- Query 6: Total revenue by channel
SELECT '=== Total Revenue by Channel (sumMap) ===' AS title;
SELECT
    sumMap(revenue_by_channel) AS total_revenue_by_channel,
    count() AS analysis_days
FROM product_analytics;

-- Query 7: Sum of conversion rates (for averaging later)
SELECT '=== Sum of Conversion Rates ===' AS title;
SELECT
    product_id,
    sumMap(conversion_rates) AS sum_conversion_rates
FROM product_analytics
GROUP BY product_id
ORDER BY product_id;

-- Query 8: Comprehensive product analytics
SELECT '=== Comprehensive Product Analytics ===' AS title;
SELECT
    product_id,
    sumMap(sales_by_region) AS total_regional_sales,
    sumMap(revenue_by_channel) AS total_channel_revenue,
    sumMap(inventory_levels) AS total_inventory_levels
FROM product_analytics
GROUP BY product_id
ORDER BY product_id;

-- Use case: mapAdd and mapSubtract for Map operations
DROP TABLE IF EXISTS inventory_changes;

CREATE TABLE inventory_changes
(
    change_id UInt32,
    change_date Date,
    additions Map(String, Int32),  -- Items added to inventory
    removals Map(String, Int32)    -- Items removed from inventory
)
ENGINE = MergeTree()
ORDER BY (change_date, change_id);

-- Insert inventory change data
INSERT INTO inventory_changes VALUES
    (1, '2025-01-01', map('item_a', 100, 'item_b', 50, 'item_c', 75), map('item_a', 30, 'item_b', 10, 'item_c', 20)),
    (2, '2025-01-01', map('item_a', 80, 'item_b', 40, 'item_c', 60), map('item_a', 25, 'item_b', 15, 'item_c', 10)),
    (3, '2025-01-02', map('item_a', 120, 'item_b', 70, 'item_c', 90), map('item_a', 40, 'item_b', 20, 'item_c', 30));

-- Query 9: Sum all additions and removals
SELECT '=== Inventory Changes Summary ===' AS title;
SELECT
    change_date,
    sumMap(additions) AS total_additions,
    sumMap(removals) AS total_removals
FROM inventory_changes
GROUP BY change_date
ORDER BY change_date;

-- Query 10: Calculate net inventory change using mapSubtract
SELECT '=== Net Inventory Change (mapSubtract) ===' AS title;
SELECT
    change_date,
    mapSubtract(sumMap(additions), sumMap(removals)) AS net_change
FROM inventory_changes
GROUP BY change_date
ORDER BY change_date;

-- Benefits of Map Aggregation
SELECT '=== Map Aggregation Benefits ===' AS info;
SELECT
    'sumMap enables direct aggregation on Map types' AS benefit_1,
    'Cleaner syntax for semi-structured data analysis' AS benefit_2,
    'Better performance than manual key extraction' AS benefit_3,
    'Ideal for dynamic schemas and flexible data models' AS benefit_4,
    'Supports mapAdd, mapSubtract for Map operations' AS benefit_5;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'E-commerce analytics with dynamic dimensions' AS use_case_1,
    'IoT sensor data aggregation' AS use_case_2,
    'User behavior tracking with flexible metrics' AS use_case_3,
    'Multi-dimensional business intelligence' AS use_case_4,
    'Product analytics with varying attributes' AS use_case_5,
    'Financial data with dynamic categories' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE inventory_changes;
-- DROP TABLE product_analytics;
-- DROP TABLE user_metrics;

SELECT '✅ Map Aggregation Test Complete!' AS status;
