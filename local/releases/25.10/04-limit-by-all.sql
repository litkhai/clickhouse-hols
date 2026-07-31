-- ClickHouse 25.10 Feature: LIMIT BY ALL
-- Purpose: Test the LIMIT BY ALL syntax
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-10

-- LIMIT n BY ALL is shorthand for "LIMIT n BY <every column in the SELECT
-- list>". ALL *replaces* the column list, so `LIMIT n BY ALL col` is a syntax
-- error: choose the SELECT list to express the key you want to group by.

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
    (1, 101, 'page_view', '/home',     '2025-10-01 10:00:00', 'sess_a'),
    (2, 101, 'page_view', '/products', '2025-10-01 10:01:00', 'sess_a'),
    (3, 101, 'click',     '/products', '2025-10-01 10:02:00', 'sess_a'),
    (4, 101, 'page_view', '/cart',     '2025-10-01 10:03:00', 'sess_a'),
    (5, 102, 'page_view', '/home',     '2025-10-01 11:00:00', 'sess_b'),
    (6, 102, 'click',     '/home',     '2025-10-01 11:01:00', 'sess_b'),
    (7, 102, 'page_view', '/about',    '2025-10-01 11:02:00', 'sess_b'),
    (8, 103, 'page_view', '/home',     '2025-10-01 12:00:00', 'sess_c'),
    (9, 103, 'page_view', '/products', '2025-10-01 12:01:00', 'sess_c'),
    (10, 103, 'click',    '/products', '2025-10-01 12:02:00', 'sess_c'),
    (11, 103, 'purchase', '/checkout', '2025-10-01 12:03:00', 'sess_c'),
    (12, 104, 'page_view', '/home',    '2025-10-01 13:00:00', 'sess_d');

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

-- Query 3: LIMIT BY ALL - NEW in 25.10
-- The SELECT list is (user_id, event_type), so ALL means "by user_id,
-- event_type" — one row per user per event type.
SELECT '=== LIMIT BY ALL (1 per user + event_type) ===' AS title;
SELECT
    user_id,
    event_type
FROM website_events
ORDER BY user_id, event_type
LIMIT 1 BY ALL;

-- Query 4: The same query written the old way, for comparison
SELECT '=== Equivalent explicit form ===' AS title;
SELECT
    user_id,
    event_type
FROM website_events
ORDER BY user_id, event_type
LIMIT 1 BY user_id, event_type;

-- Query 5: Widening the SELECT list widens the key
-- Adding page_url makes the key (user_id, event_type, page_url), so a user can
-- now appear more than once per event type.
SELECT '=== ALL follows the SELECT list ===' AS title;
SELECT
    user_id,
    event_type,
    page_url
FROM website_events
ORDER BY user_id, event_type, page_url
LIMIT 1 BY ALL;

-- Query 6: Two rows per distinct combination
SELECT '=== 2 per (event_type, page_url) ===' AS title;
SELECT
    event_type,
    page_url
FROM website_events
ORDER BY event_type, page_url
LIMIT 2 BY ALL;

-- Query 7: Deduplication - keep one row per full row shape
SELECT '=== Deduplicate on every projected column ===' AS title;
SELECT
    user_id,
    event_type,
    page_url
FROM website_events
ORDER BY user_id, event_type, page_url
LIMIT 1 BY ALL;

-- Query 8: With aggregation - top page per event type
-- GROUP BY produces (event_type, page_url, visit_count); limiting BY ALL here
-- would key on the count too, so keep the explicit form when the key is a
-- subset of the SELECT list.
SELECT '=== Top page per event type (explicit key) ===' AS title;
SELECT
    event_type,
    page_url,
    count() AS visit_count
FROM website_events
GROUP BY event_type, page_url
ORDER BY event_type, visit_count DESC
LIMIT 1 BY event_type;

-- Query 9: Count comparison
SELECT '=== Count Comparison ===' AS title;
SELECT 'Total events' AS metric, count() AS count FROM website_events
UNION ALL
SELECT 'Distinct (user_id, event_type)' AS metric, count() AS count
FROM (SELECT user_id, event_type FROM website_events LIMIT 1 BY ALL)
UNION ALL
SELECT 'After LIMIT 2 BY user_id' AS metric, count() AS count
FROM (SELECT * FROM website_events LIMIT 2 BY user_id);

-- Query 10: Session analysis - first event per session
SELECT '=== One event per session ===' AS title;
SELECT
    session_id,
    user_id
FROM website_events
ORDER BY session_id, user_id
LIMIT 1 BY ALL;

-- Notes
SELECT '=== LIMIT BY ALL Notes ===' AS info;
SELECT
    'ALL replaces the BY column list; it cannot be combined with one' AS note_1,
    'The key is exactly the SELECT list, so projection choice is the control' AS note_2,
    'Use the explicit form when the key is a subset of the selected columns' AS note_3;

-- Cleanup
-- DROP TABLE website_events;

SELECT 'LIMIT BY ALL test complete' AS status;
