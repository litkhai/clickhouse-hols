-- ClickHouse 25.3 LTS: Query Condition Cache Test
-- New Feature: use_query_condition_cache remembers, per granule, that a WHERE
--              condition matched nothing, so a repeated filter skips those
--              granules without re-evaluating them.
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- This is not a result cache. It caches the *negative* answer at granule
-- granularity: "no row in this granule satisfies that predicate". A later query
-- with the same condition therefore reads less, even if it selects other
-- columns or aggregates differently.

-- ============================================
-- 1. A Table Worth Filtering
-- ============================================

SELECT '========== 1. Test Data ==========';

DROP TABLE IF EXISTS web_logs;

CREATE TABLE web_logs
(
    log_id     UInt64,
    ts         DateTime,
    status     UInt16,
    endpoint   String,
    latency_ms UInt32,
    bytes_sent UInt64
)
ENGINE = MergeTree
ORDER BY log_id;

-- status 500 appears in a narrow id range, so most granules cannot contain it.
INSERT INTO web_logs
SELECT
    number,
    toDateTime('2025-03-20 00:00:00') + intDiv(number, 30),
    multiIf(number BETWEEN 2000000 AND 2000500, 500,
            number % 50 = 0, 404,
            200),
    ['/api/users', '/api/orders', '/health', '/static/app.js'][number % 4 + 1],
    (number % 900) + 10,
    (number % 50000) + 500
FROM numbers(3000000);

SELECT count() AS rows, countIf(status = 500) AS errors FROM web_logs;

-- ============================================
-- 2. The Setting
-- ============================================

SELECT '========== 2. use_query_condition_cache ==========';

SELECT name, value, description
FROM system.settings
WHERE name = 'use_query_condition_cache';

-- ============================================
-- 3. The Cache Starts Empty
-- ============================================

SELECT '========== 3. Empty Cache ==========';

SYSTEM DROP QUERY CONDITION CACHE;

SELECT count() AS cached_entries FROM system.query_condition_cache;

-- ============================================
-- 4. First Run — Populates the Cache
-- ============================================

SELECT '========== 4. First Run With the Cache Enabled ==========';

SELECT count() AS errors, max(latency_ms) AS worst_latency
FROM web_logs
WHERE status = 500
SETTINGS use_query_condition_cache = 1;

SELECT count() AS cached_entries FROM system.query_condition_cache;

-- ============================================
-- 5. What Got Cached
-- ============================================

SELECT '========== 5. Cache Contents ==========';

-- One entry per (table part, condition): the mark bitmap records which
-- granules of that part can still match.
SELECT
    part_name,
    key_hash != 0        AS has_condition_hash,
    length(matching_marks) AS mark_bitmap_bytes
FROM system.query_condition_cache
ORDER BY part_name
LIMIT 5;

-- ============================================
-- 6. Second Run — Same Condition
-- ============================================

SELECT '========== 6. Repeating the Same Filter ==========';

-- Identical predicate, different projection and aggregate. The cache is keyed
-- on the condition, not on the whole query, so this run still benefits.
SELECT count() AS errors, avg(bytes_sent) AS avg_bytes
FROM web_logs
WHERE status = 500
SETTINGS use_query_condition_cache = 1;

SELECT '========== 6b. And With Another Column ==========';

SELECT endpoint, count() AS errors
FROM web_logs
WHERE status = 500
GROUP BY endpoint
ORDER BY errors DESC
SETTINGS use_query_condition_cache = 1;

-- ============================================
-- 7. Correctness Against the Uncached Path
-- ============================================

SELECT '========== 7. Cached and Uncached Agree ==========';

SELECT
    (SELECT count() FROM web_logs WHERE status = 500 SETTINGS use_query_condition_cache = 1) AS cached,
    (SELECT count() FROM web_logs WHERE status = 500 SETTINGS use_query_condition_cache = 0) AS uncached,
    cached = uncached AS identical;

-- ============================================
-- 8. A Different Condition Is a Different Entry
-- ============================================

SELECT '========== 8. Separate Conditions, Separate Entries ==========';

SELECT count() AS not_found FROM web_logs WHERE status = 404
SETTINGS use_query_condition_cache = 1;

SELECT count() AS slow FROM web_logs WHERE latency_ms > 890
SETTINGS use_query_condition_cache = 1;

SELECT count() AS cached_entries FROM system.query_condition_cache;

-- ============================================
-- 9. Where It Does Not Help
-- ============================================

SELECT '========== 9. A Predicate Most Granules Satisfy ==========';

-- status = 200 matches nearly every granule, so there is nothing to skip and
-- the cache has no negative answers to record.
SELECT count() AS ok_responses FROM web_logs WHERE status = 200
SETTINGS use_query_condition_cache = 1;

-- ============================================
-- 10. Invalidation
-- ============================================

SELECT '========== 10. Dropping the Cache ==========';

SYSTEM DROP QUERY CONDITION CACHE;

SELECT count() AS cached_entries_after_drop FROM system.query_condition_cache;

-- New data invalidates the affected entries too, so the cache cannot go stale
-- against an insert.
INSERT INTO web_logs VALUES
    (9000000, '2025-03-21 00:00:00', 500, '/api/users', 950, 1024);

SELECT count() AS errors_after_insert FROM web_logs WHERE status = 500
SETTINGS use_query_condition_cache = 1;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS web_logs;

SELECT '========== Test Complete ==========';
SELECT 'The cache remembers which granules cannot match, not which rows did.' AS summary;
