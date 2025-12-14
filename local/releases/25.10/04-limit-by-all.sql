-- ClickHouse 25.10 Feature: LIMIT BY ALL
-- Purpose: Test new LIMIT BY ALL syntax to limit duplicate records
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- Create sample table with duplicate data
DROP TABLE IF EXISTS website_events;

CREATE TABLE website_events
(
    event_id UInt32,
    user_id UInt32,
    event_type String,
    page_url String,
    event_timestamp DateTime,
    session_id String
)
ENGINE = MergeTree()
ORDER BY (user_id, event_timestamp);

-- Insert sample data with duplicates
INSERT INTO website_events VALUES
    (1, 101, 'page_view', '/home', '2024-10-01 10:00:00', 'sess_001'),
    (2, 101, 'page_view', '/products', '2024-10-01 10:05:00', 'sess_001'),
    (3, 101, 'click', '/products/item1', '2024-10-01 10:10:00', 'sess_001'),
    (4, 101, 'page_view', '/cart', '2024-10-01 10:15:00', 'sess_001'),
    (5, 102, 'page_view', '/home', '2024-10-01 11:00:00', 'sess_002'),
    (6, 102, 'page_view', '/about', '2024-10-01 11:05:00', 'sess_002'),
    (7, 102, 'click', '/contact', '2024-10-01 11:10:00', 'sess_002'),
    (8, 103, 'page_view', '/home', '2024-10-01 12:00:00', 'sess_003'),
    (9, 103, 'page_view', '/products', '2024-10-01 12:05:00', 'sess_003'),
    (10, 103, 'page_view', '/products/item2', '2024-10-01 12:10:00', 'sess_003'),
    (11, 103, 'click', '/products/item2', '2024-10-01 12:15:00', 'sess_003'),
    (12, 103, 'page_view', '/checkout', '2024-10-01 12:20:00', 'sess_003'),
    (13, 104, 'page_view', '/home', '2024-10-01 13:00:00', 'sess_004'),
    (14, 104, 'page_view', '/blog', '2024-10-01 13:05:00', 'sess_004'),
    (15, 105, 'page_view', '/home', '2024-10-01 14:00:00', 'sess_005'),
    (16, 105, 'click', '/home', '2024-10-01 14:02:00', 'sess_005'),
    (17, 105, 'page_view', '/products', '2024-10-01 14:05:00', 'sess_005');

-- Query 1: View all events
SELECT '=== All Events ===' AS title;
SELECT * FROM website_events ORDER BY user_id, event_timestamp;

-- Query 2: Traditional LIMIT BY - limit events per user
SELECT '=== Traditional LIMIT BY (2 events per user) ===' AS title;
SELECT
    user_id,
    event_type,
    page_url,
    event_timestamp
FROM website_events
ORDER BY user_id, event_timestamp
LIMIT 2 BY user_id;

-- Query 3: LIMIT BY ALL - NEW in 25.10!
-- Take up to N records for EACH unique value combination
SELECT '=== LIMIT BY ALL (2 per user) ===' AS title;
SELECT
    user_id,
    event_type,
    page_url,
    event_timestamp
FROM website_events
ORDER BY user_id, event_timestamp
LIMIT 2 BY ALL user_id;

-- Query 4: LIMIT BY ALL with multiple columns
SELECT '=== LIMIT BY ALL (1 per user + event_type) ===' AS title;
SELECT
    user_id,
    event_type,
    count() as event_count,
    page_url,
    event_timestamp
FROM website_events
ORDER BY user_id, event_type, event_timestamp
LIMIT 1 BY ALL user_id, event_type;

-- Query 5: LIMIT BY ALL for data sampling
SELECT '=== Sample 2 events from each event_type ===' AS title;
SELECT
    event_type,
    user_id,
    page_url,
    event_timestamp
FROM website_events
ORDER BY event_type, event_timestamp
LIMIT 2 BY ALL event_type;

-- Query 6: Practical use case - Get first and last event per user
SELECT '=== First Event per User ===' AS title;
SELECT
    user_id,
    event_type AS first_event_type,
    page_url AS first_page,
    event_timestamp AS first_event_time
FROM website_events
ORDER BY user_id, event_timestamp
LIMIT 1 BY ALL user_id;

SELECT '=== Last Event per User ===' AS title;
SELECT
    user_id,
    event_type AS last_event_type,
    page_url AS last_page,
    event_timestamp AS last_event_time
FROM website_events
ORDER BY user_id, event_timestamp DESC
LIMIT 1 BY ALL user_id;

-- Query 7: LIMIT BY ALL with aggregation
SELECT '=== Top 2 Pages per Event Type ===' AS title;
SELECT
    event_type,
    page_url,
    count() AS visit_count
FROM website_events
GROUP BY event_type, page_url
ORDER BY event_type, visit_count DESC
LIMIT 2 BY ALL event_type;

-- Query 8: LIMIT BY ALL for deduplication preview
SELECT '=== Deduplicate - Keep First Event per User+Type ===' AS title;
SELECT
    user_id,
    event_type,
    page_url,
    event_timestamp,
    session_id
FROM website_events
ORDER BY user_id, event_type, event_timestamp
LIMIT 1 BY ALL user_id, event_type;

-- Query 9: Compare counts - before and after LIMIT BY ALL
SELECT '=== Count Comparison ===' AS title;
SELECT
    'Total Events' AS metric,
    count() AS count
FROM website_events
UNION ALL
SELECT
    'After LIMIT 2 BY user_id' AS metric,
    count() AS count
FROM (
    SELECT *
    FROM website_events
    LIMIT 2 BY user_id
);

-- Query 10: Practical use case - Session analysis
SELECT '=== First 3 Events per Session ===' AS title;
SELECT
    session_id,
    user_id,
    event_type,
    page_url,
    event_timestamp
FROM website_events
ORDER BY session_id, event_timestamp
LIMIT 3 BY ALL session_id;

-- Benefits of LIMIT BY ALL
SELECT '=== LIMIT BY ALL Benefits ===' AS info;
SELECT
    'Simplified syntax for limiting per group' AS benefit_1,
    'More intuitive than window functions for sampling' AS benefit_2,
    'Better performance for deduplication queries' AS benefit_3,
    'Useful for data quality checks and sampling' AS benefit_4;

-- Cleanup
-- DROP TABLE website_events;

SELECT '✅ LIMIT BY ALL Test Complete!' AS status;
