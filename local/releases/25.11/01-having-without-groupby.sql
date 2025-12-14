-- ClickHouse 25.11 Feature: HAVING without GROUP BY
-- Purpose: Test HAVING clause support without GROUP BY for ANSI SQL compatibility
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Drop table if exists
DROP TABLE IF EXISTS sales_transactions;

-- Create a table for sales data
CREATE TABLE sales_transactions
(
    transaction_id UInt64,
    transaction_date Date,
    customer_id UInt32,
    product_name String,
    quantity UInt32,
    unit_price Decimal(10, 2),
    total_amount Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY transaction_date;

-- Insert sample sales data
INSERT INTO sales_transactions VALUES
    (1, '2025-01-01', 101, 'Laptop', 2, 999.99, 1999.98),
    (2, '2025-01-01', 102, 'Mouse', 5, 29.99, 149.95),
    (3, '2025-01-02', 103, 'Keyboard', 3, 79.99, 239.97),
    (4, '2025-01-02', 101, 'Monitor', 1, 299.99, 299.99),
    (5, '2025-01-03', 104, 'Headphones', 4, 149.99, 599.96),
    (6, '2025-01-03', 102, 'Webcam', 2, 89.99, 179.98),
    (7, '2025-01-04', 105, 'USB Cable', 10, 9.99, 99.90),
    (8, '2025-01-04', 103, 'Charger', 3, 39.99, 119.97),
    (9, '2025-01-05', 106, 'Mouse Pad', 6, 14.99, 89.94),
    (10, '2025-01-05', 104, 'Docking Station', 1, 199.99, 199.99);

-- Query 1: View all transactions
SELECT '=== All Transactions ===' AS title;
SELECT * FROM sales_transactions ORDER BY transaction_id;

-- Query 2: Traditional HAVING with GROUP BY
SELECT '=== Traditional: HAVING with GROUP BY ===' AS title;
SELECT
    customer_id,
    sum(total_amount) AS total_spent
FROM sales_transactions
GROUP BY customer_id
HAVING total_spent > 300
ORDER BY total_spent DESC;

-- Query 3: NEW FEATURE - HAVING without GROUP BY
-- This filters the entire result set based on aggregate conditions
SELECT '=== NEW: HAVING without GROUP BY ===' AS title;
SELECT
    sum(total_amount) AS grand_total,
    avg(total_amount) AS avg_transaction,
    count() AS transaction_count
FROM sales_transactions
HAVING grand_total > 3000;

-- Query 4: HAVING without GROUP BY - Filter on count
SELECT '=== HAVING on Count (without GROUP BY) ===' AS title;
SELECT
    count() AS total_transactions,
    sum(total_amount) AS revenue
FROM sales_transactions
HAVING total_transactions >= 10;

-- Query 5: HAVING without GROUP BY - Multiple conditions
SELECT '=== HAVING with Multiple Conditions ===' AS title;
SELECT
    sum(total_amount) AS total_revenue,
    avg(unit_price) AS avg_price,
    max(total_amount) AS largest_transaction
FROM sales_transactions
HAVING total_revenue > 3000 AND avg_price < 200;

-- Real-world use case: Validate aggregate constraints
DROP TABLE IF EXISTS daily_metrics;

CREATE TABLE daily_metrics
(
    metric_date Date,
    metric_name String,
    metric_value Float64,
    metric_unit String
)
ENGINE = MergeTree()
ORDER BY metric_date;

-- Insert sample metrics data
INSERT INTO daily_metrics VALUES
    ('2025-01-01', 'revenue', 15000.50, 'USD'),
    ('2025-01-01', 'orders', 250, 'count'),
    ('2025-01-01', 'visitors', 3500, 'count'),
    ('2025-01-02', 'revenue', 18500.75, 'USD'),
    ('2025-01-02', 'orders', 310, 'count'),
    ('2025-01-02', 'visitors', 4200, 'count'),
    ('2025-01-03', 'revenue', 12000.00, 'USD'),
    ('2025-01-03', 'orders', 180, 'count'),
    ('2025-01-03', 'visitors', 2800, 'count');

-- Query 6: Check if total metrics meet threshold
SELECT '=== Validate Total Revenue Threshold ===' AS title;
SELECT
    'Total metrics summary' AS description,
    sum(metric_value) AS total_value,
    count() AS metric_count
FROM daily_metrics
WHERE metric_name = 'revenue'
HAVING total_value > 40000;

-- Query 7: Average order value validation
SELECT '=== Validate Average Order Value ===' AS title;
SELECT
    avg(CASE WHEN metric_name = 'revenue' THEN metric_value ELSE 0 END) AS avg_daily_revenue,
    avg(CASE WHEN metric_name = 'orders' THEN metric_value ELSE 0 END) AS avg_daily_orders
FROM daily_metrics
HAVING avg_daily_revenue > 10000;

-- Query 8: Quality threshold check
SELECT '=== Quality Threshold Check ===' AS title;
SELECT
    count(DISTINCT metric_date) AS days_recorded,
    count(DISTINCT metric_name) AS metrics_tracked,
    sum(metric_value) AS total_value
FROM daily_metrics
HAVING days_recorded >= 3 AND metrics_tracked >= 3;

-- PostgreSQL compatibility example
DROP TABLE IF EXISTS test_scores;

CREATE TABLE test_scores
(
    student_id UInt32,
    test_name String,
    score UInt8
)
ENGINE = MergeTree()
ORDER BY student_id;

INSERT INTO test_scores VALUES
    (1, 'Math', 85),
    (1, 'Science', 90),
    (2, 'Math', 78),
    (2, 'Science', 82),
    (3, 'Math', 92),
    (3, 'Science', 88);

-- Query 9: PostgreSQL-style HAVING without GROUP BY
SELECT '=== PostgreSQL Compatibility: Class Average Check ===' AS title;
SELECT
    avg(score) AS class_average,
    count() AS total_tests,
    min(score) AS lowest_score,
    max(score) AS highest_score
FROM test_scores
HAVING class_average > 80;

-- Query 10: Conditional filtering with HAVING
SELECT '=== Conditional Quality Check ===' AS title;
SELECT
    count() AS test_count,
    avg(score) AS avg_score,
    stddevPop(score) AS score_stddev
FROM test_scores
WHERE test_name = 'Math'
HAVING avg_score > 75 AND score_stddev < 10;

-- Benefits of HAVING without GROUP BY
SELECT '=== HAVING without GROUP BY Benefits ===' AS info;
SELECT
    'Improved ANSI SQL compatibility' AS benefit_1,
    'Better PostgreSQL migration support' AS benefit_2,
    'Simplified aggregate validation queries' AS benefit_3,
    'Filter results based on aggregate conditions' AS benefit_4,
    'Useful for data quality checks' AS benefit_5;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Data quality validation' AS use_case_1,
    'Aggregate threshold checks' AS use_case_2,
    'Business rule validation' AS use_case_3,
    'PostgreSQL query migration' AS use_case_4,
    'Single-row aggregate filtering' AS use_case_5,
    'ETL pipeline quality gates' AS use_case_6;

-- Comparison: Traditional vs New Syntax
SELECT '=== Syntax Comparison ===' AS title;
SELECT
    'Traditional: Requires GROUP BY even for simple checks' AS old_way,
    'ClickHouse 25.11: HAVING works without GROUP BY' AS new_way,
    'Benefit: Cleaner, more intuitive SQL for aggregate filters' AS advantage;

-- Cleanup (commented out for inspection)
-- DROP TABLE test_scores;
-- DROP TABLE daily_metrics;
-- DROP TABLE sales_transactions;

SELECT '✅ HAVING without GROUP BY Test Complete!' AS status;
