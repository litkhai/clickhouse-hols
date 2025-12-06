-- ClickHouse 25.9 Feature: Streaming Secondary Indices
-- Purpose: Test streaming secondary indices for faster query startup
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-09

-- ==========================================
-- Test 1: Setup - Create Table with Secondary Index
-- ==========================================

SELECT '=== Test 1: Creating Table with Streaming Secondary Index ===' AS title;

SELECT '\n🚀 ClickHouse 25.9 New Feature: Streaming Secondary Indices\nReading indices happens together with scanning data for faster query startup\n' AS info;

DROP TABLE IF EXISTS events;

CREATE TABLE events
(
    event_id UInt64,
    event_time DateTime,
    user_id UInt32,
    event_type String,
    page_url String,
    session_id String,
    duration_ms UInt32,
    INDEX user_idx user_id TYPE minmax GRANULARITY 4,
    INDEX type_idx event_type TYPE set(100) GRANULARITY 4,
    INDEX time_idx event_time TYPE minmax GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY (event_time, event_id)
SETTINGS index_granularity = 8192;

SELECT '✅ Created events table with multiple secondary indices' AS status;

-- ==========================================
-- Test 2: Insert Sample Event Data
-- ==========================================

SELECT '=== Test 2: Inserting Sample Events ===' AS title;

INSERT INTO events
SELECT
    number + 1 AS event_id,
    now() - INTERVAL (number % 86400) SECOND AS event_time,
    (number % 100000) + 1 AS user_id,
    ['page_view', 'click', 'scroll', 'form_submit', 'video_play'][1 + (number % 5)] AS event_type,
    concat('https://example.com/page', toString((number % 1000) + 1)) AS page_url,
    concat('session_', toString((number % 50000) + 1)) AS session_id,
    (number % 10000) + 100 AS duration_ms
FROM numbers(5000000);

SELECT format('✅ Inserted {0} events', count()) AS status FROM events;

-- ==========================================
-- Test 3: Query with Streaming Indices (Enabled)
-- ==========================================

SELECT '=== Test 3: Query with Streaming Indices ===' AS title;

-- Enable streaming indices
SET use_skip_indexes_on_data_read = 1;

SELECT '\n⚡ Streaming indices ENABLED - faster query startup\n' AS mode;

SELECT
    event_type,
    count() AS event_count,
    round(avg(duration_ms), 2) AS avg_duration,
    min(event_time) AS first_event,
    max(event_time) AS last_event
FROM events
WHERE user_id BETWEEN 1000 AND 2000
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY event_type
ORDER BY event_count DESC
LIMIT 10;

-- ==========================================
-- Test 4: Query without Streaming Indices (Comparison)
-- ==========================================

SELECT '=== Test 4: Query without Streaming Indices ===' AS title;

-- Disable streaming indices to see the difference
SET use_skip_indexes_on_data_read = 0;

SELECT '\n🐢 Streaming indices DISABLED - traditional index reading\n' AS mode;

SELECT
    event_type,
    count() AS event_count,
    round(avg(duration_ms), 2) AS avg_duration
FROM events
WHERE user_id BETWEEN 1000 AND 2000
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY event_type
ORDER BY event_count DESC
LIMIT 10;

-- Re-enable for remaining tests
SET use_skip_indexes_on_data_read = 1;

-- ==========================================
-- Test 5: LIMIT Queries with Streaming Indices
-- ==========================================

SELECT '=== Test 5: LIMIT Queries Benefit from Streaming ===' AS title;

SELECT '\n🎯 Streaming indices enable early query termination when LIMIT is reached\n' AS benefit;

-- Query with LIMIT - streaming indices allow early exit
SELECT
    event_id,
    event_time,
    user_id,
    event_type,
    duration_ms
FROM events
WHERE event_type = 'video_play'
  AND duration_ms > 5000
ORDER BY event_time DESC
LIMIT 100;

SELECT format('✅ Retrieved top 100 events efficiently using streaming indices') AS status;

-- ==========================================
-- Test 6: Session Analysis with Indices
-- ==========================================

SELECT '=== Test 6: Session Analysis ===' AS title;

SELECT
    event_type,
    count(DISTINCT session_id) AS unique_sessions,
    count() AS total_events,
    round(count() / count(DISTINCT session_id), 2) AS events_per_session
FROM events
WHERE event_time >= now() - INTERVAL 2 HOUR
GROUP BY event_type
ORDER BY unique_sessions DESC;

-- ==========================================
-- Test 7: User Behavior Pattern Analysis
-- ==========================================

SELECT '=== Test 7: User Behavior Patterns ===' AS title;

WITH user_events AS (
    SELECT
        user_id,
        count() AS event_count,
        countIf(event_type = 'page_view') AS page_views,
        countIf(event_type = 'click') AS clicks,
        countIf(event_type = 'form_submit') AS conversions,
        round(avg(duration_ms), 2) AS avg_duration
    FROM events
    WHERE event_time >= now() - INTERVAL 1 DAY
    GROUP BY user_id
    HAVING event_count > 10
)
SELECT
    CASE
        WHEN conversions > 0 AND clicks > 5 THEN 'Active Converter'
        WHEN clicks > 10 THEN 'Active Browser'
        WHEN page_views > 5 THEN 'Casual Visitor'
        ELSE 'New User'
    END AS user_segment,
    count() AS users,
    round(avg(event_count), 2) AS avg_events,
    round(avg(avg_duration), 2) AS avg_time_ms
FROM user_events
GROUP BY user_segment
ORDER BY users DESC;

-- ==========================================
-- Test 8: Time-Series Analysis with Indices
-- ==========================================

SELECT '=== Test 8: Time-Series Analysis ===' AS title;

SELECT
    toStartOfHour(event_time) AS hour,
    event_type,
    count() AS events,
    count(DISTINCT user_id) AS unique_users,
    count(DISTINCT session_id) AS unique_sessions
FROM events
WHERE event_time >= now() - INTERVAL 6 HOUR
GROUP BY hour, event_type
ORDER BY hour DESC, events DESC
LIMIT 20;

-- ==========================================
-- Test 9: Page Performance Analysis
-- ==========================================

SELECT '=== Test 9: Page Performance Analysis ===' AS title;

SELECT
    page_url,
    count() AS visits,
    round(avg(duration_ms), 2) AS avg_duration,
    quantile(0.5)(duration_ms) AS median_duration,
    quantile(0.95)(duration_ms) AS p95_duration
FROM events
WHERE event_type = 'page_view'
  AND event_time >= now() - INTERVAL 3 HOUR
GROUP BY page_url
ORDER BY visits DESC
LIMIT 15;

-- ==========================================
-- Test 10: Streaming Indices Benefits
-- ==========================================

SELECT '=== ClickHouse 25.9: Streaming Indices Benefits ===' AS info;

SELECT '
🚀 Streaming Secondary Indices Benefits:

1. Performance:
   ✓ Faster query startup
   ✓ Incremental index reading
   ✓ Early query termination with LIMIT
   ✓ Reduced memory overhead

2. Architecture:
   ✓ Two-stream process: data + indices
   ✓ Granule-level filtering
   ✓ Parallel index scanning
   ✓ Efficient I/O patterns

3. Query Types Benefiting Most:
   - Queries with LIMIT clauses
   - Selective WHERE conditions
   - Time-range queries
   - User/session analysis

4. Configuration:
   SET use_skip_indexes_on_data_read = 1;

5. Index Types Supported:
   - minmax (range filtering)
   - set (value sets)
   - bloom_filter (approximate membership)
   - ngrambf_v1 (fuzzy text search)

Key Improvement: Before 25.9, ClickHouse had to read all
secondary index data upfront before starting the query. Now,
indices are read incrementally alongside the data, enabling
faster query startup and early termination.
' AS benefits;

-- Cleanup (commented out for inspection)
-- DROP TABLE events;

SELECT '✅ Streaming Secondary Indices Test Complete!' AS status;
