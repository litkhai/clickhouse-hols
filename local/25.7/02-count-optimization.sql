-- ClickHouse 25.7 Feature: count() Aggregation Optimization
-- Purpose: Test the optimized count() aggregation (20-30% faster, reduced memory)
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-07

-- Drop tables if exist
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS user_activity;

-- Create events table for testing count() optimization
CREATE TABLE events
(
    event_id UInt64,
    user_id UInt32,
    event_type String,
    event_time DateTime,
    country String,
    device_type String,
    revenue Decimal(10, 2)
)
ENGINE = MergeTree()
ORDER BY (event_time, user_id)
PARTITION BY toYYYYMM(event_time);

-- Insert large dataset (10 million events)
INSERT INTO events
SELECT
    number as event_id,
    (number % 100000) as user_id,
    ['click', 'view', 'purchase', 'signup', 'logout'][1 + (number % 5)] as event_type,
    toDateTime('2025-01-01 00:00:00') + toIntervalSecond(number % 2592000) as event_time,
    ['US', 'UK', 'DE', 'FR', 'JP', 'CN', 'IN', 'BR', 'AU', 'CA'][1 + (number % 10)] as country,
    ['mobile', 'desktop', 'tablet'][1 + (number % 3)] as device_type,
    round((number % 100), 2) as revenue
FROM numbers(10000000);

SELECT '=== Dataset Created: 10M Events ===' AS title;
SELECT
    count() as total_events,
    min(event_time) as start_time,
    max(event_time) as end_time,
    count(DISTINCT user_id) as unique_users
FROM events;

-- Test 1: Basic count() - Optimized in 25.7
SELECT '=== Test 1: Basic count() Performance ===' AS title;
SELECT count() as total_events
FROM events;

-- Test 2: count() with GROUP BY - 20-30% faster
SELECT '=== Test 2: count() with GROUP BY (Event Type) ===' AS title;
SELECT
    event_type,
    count() as event_count,
    round(count() * 100.0 / (SELECT count() FROM events), 2) as percentage
FROM events
GROUP BY event_type
ORDER BY event_count DESC;

-- Test 3: Multi-dimensional count() with GROUP BY
SELECT '=== Test 3: count() by Country and Device ===' AS title;
SELECT
    country,
    device_type,
    count() as event_count,
    round(avg(revenue), 2) as avg_revenue
FROM events
GROUP BY country, device_type
ORDER BY event_count DESC
LIMIT 20;

-- Test 4: count(DISTINCT) optimization
SELECT '=== Test 4: count(DISTINCT) Users ===' AS title;
SELECT
    event_type,
    count(DISTINCT user_id) as unique_users,
    count() as total_events,
    round(count() * 1.0 / count(DISTINCT user_id), 2) as events_per_user
FROM events
GROUP BY event_type
ORDER BY unique_users DESC;

-- Test 5: count() with complex WHERE conditions
SELECT '=== Test 5: Conditional count() with Filters ===' AS title;
SELECT
    country,
    countIf(event_type = 'purchase') as purchases,
    countIf(event_type = 'view') as views,
    countIf(event_type = 'click') as clicks,
    count() as total_events,
    round(countIf(event_type = 'purchase') * 100.0 / count(), 2) as conversion_rate
FROM events
GROUP BY country
ORDER BY purchases DESC
LIMIT 10;

-- Test 6: Time-based aggregation with count()
SELECT '=== Test 6: Hourly Event Count ===' AS title;
SELECT
    toStartOfHour(event_time) as hour,
    count() as event_count,
    count(DISTINCT user_id) as active_users,
    round(sum(revenue), 2) as total_revenue
FROM events
WHERE event_time >= '2025-01-01 00:00:00'
  AND event_time < '2025-01-02 00:00:00'
GROUP BY hour
ORDER BY hour
LIMIT 24;

-- Create a second table for JOIN scenario
CREATE TABLE user_activity
(
    user_id UInt32,
    activity_date Date,
    session_count UInt16,
    total_duration_seconds UInt32
)
ENGINE = MergeTree()
ORDER BY (user_id, activity_date);

-- Insert user activity data
INSERT INTO user_activity
SELECT
    (number % 100000) as user_id,
    toDate('2025-01-01') + toIntervalDay(number % 30) as activity_date,
    1 + (number % 20) as session_count,
    300 + (number % 7200) as total_duration_seconds
FROM numbers(500000);

SELECT '=== User Activity Table Created ===' AS title;
SELECT
    count() as total_records,
    count(DISTINCT user_id) as unique_users,
    sum(session_count) as total_sessions
FROM user_activity;

-- Test 7: count() in JOIN scenarios (optimized)
SELECT '=== Test 7: count() with JOIN ===' AS title;
SELECT
    e.event_type,
    count() as events,
    count(DISTINCT e.user_id) as users_with_events,
    round(avg(ua.session_count), 2) as avg_sessions,
    round(avg(ua.total_duration_seconds), 2) as avg_duration_sec
FROM events e
JOIN user_activity ua ON e.user_id = ua.user_id AND toDate(e.event_time) = ua.activity_date
WHERE e.event_time >= '2025-01-01' AND e.event_time < '2025-01-02'
GROUP BY e.event_type
ORDER BY events DESC;

-- Test 8: count() with subqueries (memory optimization)
SELECT '=== Test 8: count() in Subqueries ===' AS title;
SELECT
    country,
    total_users,
    active_users,
    round(active_users * 100.0 / total_users, 2) as active_rate
FROM (
    SELECT
        country,
        count(DISTINCT user_id) as total_users
    FROM events
    GROUP BY country
) t1
JOIN (
    SELECT
        country,
        count(DISTINCT user_id) as active_users
    FROM events
    WHERE event_type IN ('purchase', 'click')
    GROUP BY country
) t2 USING (country)
ORDER BY active_users DESC
LIMIT 10;

-- Test 9: Window functions with count()
SELECT '=== Test 9: count() with Window Functions ===' AS title;
SELECT
    event_type,
    country,
    events,
    sum(events) OVER (PARTITION BY event_type) as total_by_type,
    round(events * 100.0 / sum(events) OVER (PARTITION BY event_type), 2) as pct_of_type
FROM (
    SELECT
        event_type,
        country,
        count() as events
    FROM events
    GROUP BY event_type, country
) t
ORDER BY event_type, events DESC
LIMIT 25;

-- Test 10: count() with HAVING clause (optimization)
SELECT '=== Test 10: count() with HAVING Filter ===' AS title;
SELECT
    device_type,
    event_type,
    count() as event_count,
    count(DISTINCT user_id) as unique_users
FROM events
GROUP BY device_type, event_type
HAVING count() > 500000
ORDER BY event_count DESC;

-- Test 11: Performance comparison - count() vs count(column)
SELECT '=== Test 11: count() vs count(column) ===' AS title;
SELECT
    'count()' as method,
    count() as result,
    'Optimized - fastest' as note
FROM events
UNION ALL
SELECT
    'count(event_id)' as method,
    count(event_id) as result,
    'Slightly slower' as note
FROM events
UNION ALL
SELECT
    'count(DISTINCT user_id)' as method,
    count(DISTINCT user_id) as result,
    'More computation needed' as note
FROM events;

-- Test 12: Large GROUP BY with count() - Memory optimization test
SELECT '=== Test 12: High Cardinality GROUP BY ===' AS title;
SELECT
    user_id,
    count() as event_count,
    count(DISTINCT event_type) as event_types,
    sum(revenue) as total_revenue
FROM events
GROUP BY user_id
ORDER BY event_count DESC
LIMIT 20;

-- Test 13: Materialized view with count() optimization
DROP TABLE IF EXISTS event_summary;

CREATE MATERIALIZED VIEW event_summary
ENGINE = SummingMergeTree()
ORDER BY (event_type, country, event_date)
AS SELECT
    event_type,
    country,
    toDate(event_time) as event_date,
    count() as event_count,
    uniq(user_id) as unique_users,
    sum(revenue) as total_revenue
FROM events
GROUP BY event_type, country, event_date;

-- Insert trigger happens automatically on new inserts
SELECT '=== Materialized View Created ===' AS title;
SELECT
    event_type,
    country,
    sum(event_count) as total_events,
    sum(unique_users) as total_unique_users
FROM event_summary
GROUP BY event_type, country
ORDER BY total_events DESC
LIMIT 15;

-- Performance insights
SELECT '=== ClickHouse 25.7 count() Optimization Benefits ===' AS info;
SELECT
    '20-30% faster count() aggregation performance' AS benefit_1,
    'Reduced memory consumption in large GROUP BY operations' AS benefit_2,
    'Improved performance with high-cardinality dimensions' AS benefit_3,
    'Better scalability for real-time analytics' AS benefit_4,
    'Optimized count(DISTINCT) queries' AS benefit_5;

-- Use cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Real-time analytics dashboards with live counts' AS use_case_1,
    'Large-scale event tracking and user behavior analysis' AS use_case_2,
    'Multi-dimensional business intelligence reporting' AS use_case_3,
    'Log aggregation and monitoring systems' AS use_case_4,
    'E-commerce analytics with conversion funnels' AS use_case_5,
    'IoT data processing and device telemetry' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE event_summary;
-- DROP TABLE user_activity;
-- DROP TABLE events;

SELECT '✅ count() Optimization Test Complete!' AS status;
