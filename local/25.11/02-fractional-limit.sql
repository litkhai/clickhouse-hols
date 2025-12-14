-- ClickHouse 25.11 Feature: Fractional LIMIT/OFFSET
-- Purpose: Test fractional limits for sampling and data analysis
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- Drop table if exists
DROP TABLE IF EXISTS customer_database;

-- Create a table with customer data
CREATE TABLE customer_database
(
    customer_id UInt32,
    customer_name String,
    email String,
    signup_date Date,
    total_purchases UInt32,
    total_spent Decimal(10, 2),
    customer_segment String
)
ENGINE = MergeTree()
ORDER BY customer_id;

-- Insert sample customer data (100 customers)
INSERT INTO customer_database
SELECT
    number AS customer_id,
    concat('Customer_', toString(number)) AS customer_name,
    concat('customer', toString(number), '@example.com') AS email,
    today() - INTERVAL (rand() % 365) DAY AS signup_date,
    rand() % 50 + 1 AS total_purchases,
    round((rand() % 10000) / 100, 2) AS total_spent,
    CASE
        WHEN (rand() % 100) < 20 THEN 'VIP'
        WHEN (rand() % 100) < 50 THEN 'Premium'
        ELSE 'Standard'
    END AS customer_segment
FROM numbers(100);

-- Query 1: View total customer count
SELECT '=== Total Customers ===' AS title;
SELECT count() AS total_customers FROM customer_database;

-- Query 2: Traditional LIMIT - Get first 10 rows
SELECT '=== Traditional LIMIT: First 10 Customers ===' AS title;
SELECT customer_id, customer_name, customer_segment, total_spent
FROM customer_database
ORDER BY customer_id
LIMIT 10;

-- Query 3: NEW FEATURE - Fractional LIMIT (10% of data)
SELECT '=== NEW: Fractional LIMIT 0.1 (10% of data) ===' AS title;
SELECT
    customer_id,
    customer_name,
    customer_segment,
    total_spent
FROM customer_database
ORDER BY customer_id
LIMIT 0.1;

-- Query 4: Fractional LIMIT 0.25 (25% of data)
SELECT '=== Fractional LIMIT 0.25 (25% sample) ===' AS title;
SELECT
    customer_segment,
    count() AS customer_count,
    avg(total_spent) AS avg_spent
FROM (
    SELECT * FROM customer_database
    LIMIT 0.25
)
GROUP BY customer_segment
ORDER BY customer_count DESC;

-- Query 5: Fractional LIMIT 0.5 (50% of data) with aggregation
SELECT '=== Fractional LIMIT 0.5 (50% sample) ===' AS title;
SELECT
    count() AS sample_size,
    avg(total_purchases) AS avg_purchases,
    avg(total_spent) AS avg_spending,
    min(total_spent) AS min_spent,
    max(total_spent) AS max_spent
FROM customer_database
LIMIT 0.5;

-- Query 6: Fractional LIMIT for quick data preview (5%)
SELECT '=== Quick Data Preview: 5% Sample ===' AS title;
SELECT
    customer_id,
    customer_name,
    email,
    customer_segment,
    total_spent
FROM customer_database
ORDER BY customer_id
LIMIT 0.05;

-- Real-world use case: Large dataset sampling
DROP TABLE IF EXISTS web_events;

CREATE TABLE web_events
(
    event_id UInt64,
    user_id UInt32,
    event_type String,
    event_timestamp DateTime,
    page_url String,
    session_id String,
    device_type String
)
ENGINE = MergeTree()
ORDER BY event_timestamp;

-- Insert large sample event data (10,000 events)
INSERT INTO web_events
SELECT
    number AS event_id,
    (rand() % 1000) + 1 AS user_id,
    CASE (rand() % 5)
        WHEN 0 THEN 'page_view'
        WHEN 1 THEN 'click'
        WHEN 2 THEN 'scroll'
        WHEN 3 THEN 'form_submit'
        ELSE 'download'
    END AS event_type,
    now() - INTERVAL (rand() % 86400) SECOND AS event_timestamp,
    concat('/page/', toString(rand() % 100)) AS page_url,
    concat('session_', toString(rand() % 500)) AS session_id,
    CASE (rand() % 3)
        WHEN 0 THEN 'mobile'
        WHEN 1 THEN 'desktop'
        ELSE 'tablet'
    END AS device_type
FROM numbers(10000);

-- Query 7: Sample 1% of web events for quick analysis
SELECT '=== 1% Sample: Event Type Distribution ===' AS title;
SELECT
    event_type,
    count() AS event_count
FROM (SELECT * FROM web_events LIMIT 0.01)
GROUP BY event_type
ORDER BY event_count DESC;

-- Query 8: Sample 10% for device analysis
SELECT '=== 10% Sample: Device Distribution ===' AS title;
SELECT
    device_type,
    count() AS device_count,
    countDistinct(user_id) AS unique_users
FROM (
    SELECT * FROM web_events
    LIMIT 0.1
)
GROUP BY device_type
ORDER BY device_count DESC;

-- Query 9: Sample 20% for hourly activity pattern
SELECT '=== 20% Sample: Hourly Activity ===' AS title;
SELECT
    toHour(event_timestamp) AS hour_of_day,
    count() AS events,
    countDistinct(user_id) AS unique_users,
    countDistinct(session_id) AS unique_sessions
FROM (
    SELECT * FROM web_events
    LIMIT 0.2
)
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Query 10: Compare full dataset vs sampled dataset
SELECT '=== Comparison: Full vs Sampled (10%) ===' AS title;
SELECT
    'Full Dataset' AS dataset_type,
    count() AS total_events,
    countDistinct(user_id) AS unique_users,
    countDistinct(event_type) AS event_types
FROM web_events
UNION ALL
SELECT
    '10% Sample' AS dataset_type,
    count() AS total_events,
    countDistinct(user_id) AS unique_users,
    countDistinct(event_type) AS event_types
FROM (SELECT * FROM web_events LIMIT 0.1);

-- Use case: ML training data sampling
DROP TABLE IF EXISTS training_data;

CREATE TABLE training_data
(
    data_id UInt64,
    feature_1 Float32,
    feature_2 Float32,
    feature_3 Float32,
    feature_4 Float32,
    label UInt8
)
ENGINE = MergeTree()
ORDER BY data_id;

-- Generate synthetic training data (50,000 rows)
INSERT INTO training_data
SELECT
    number AS data_id,
    rand() / 4294967295.0 AS feature_1,
    rand() / 4294967295.0 AS feature_2,
    rand() / 4294967295.0 AS feature_3,
    rand() / 4294967295.0 AS feature_4,
    rand() % 2 AS label
FROM numbers(50000);

-- Query 11: Sample 5% for quick model prototyping
SELECT '=== ML Data: 5% Sample for Prototyping ===' AS title;
SELECT
    count() AS sample_size,
    avg(feature_1) AS avg_f1,
    avg(feature_2) AS avg_f2,
    avg(feature_3) AS avg_f3,
    avg(feature_4) AS avg_f4,
    sum(label) AS positive_labels,
    count() - sum(label) AS negative_labels
FROM training_data
LIMIT 0.05;

-- Query 12: Sample 30% for validation set
SELECT '=== ML Data: 30% Sample for Validation ===' AS title;
SELECT
    label,
    count() AS count
FROM (SELECT * FROM training_data LIMIT 0.3)
GROUP BY label
ORDER BY label;

-- Query 13: Multiple fractional samples for A/B testing
SELECT '=== A/B Test Groups: Different Samples ===' AS title;
SELECT
    'Group A (10%)' AS test_group,
    count() AS size
FROM customer_database
LIMIT 0.1
UNION ALL
SELECT
    'Group B (15%)' AS test_group,
    count() AS size
FROM customer_database
LIMIT 0.15
UNION ALL
SELECT
    'Control Group (5%)' AS test_group,
    count() AS size
FROM customer_database
LIMIT 0.05;

-- Benefits of Fractional LIMIT
SELECT '=== Fractional LIMIT Benefits ===' AS info;
SELECT
    'Quick data sampling without calculating exact row counts' AS benefit_1,
    'Ideal for exploratory data analysis' AS benefit_2,
    'Fast prototyping with large datasets' AS benefit_3,
    'Consistent sampling methodology' AS benefit_4,
    'Useful for ML training/validation splits' AS benefit_5;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Exploratory data analysis on large datasets' AS use_case_1,
    'Quick statistical sampling' AS use_case_2,
    'Machine learning train/test split' AS use_case_3,
    'A/B testing group creation' AS use_case_4,
    'Data quality checks on samples' AS use_case_5,
    'Performance testing with representative data' AS use_case_6,
    'Ad-hoc analysis without full scan' AS use_case_7;

-- Performance note
SELECT '=== Performance Note ===' AS info;
SELECT
    'Fractional LIMIT is more intuitive than calculating exact row numbers' AS note_1,
    'Useful when you need "approximately X% of data"' AS note_2,
    'Combines well with OFFSET for pagination' AS note_3;

-- Cleanup (commented out for inspection)
-- DROP TABLE training_data;
-- DROP TABLE web_events;
-- DROP TABLE customer_database;

SELECT '✅ Fractional LIMIT Test Complete!' AS status;
