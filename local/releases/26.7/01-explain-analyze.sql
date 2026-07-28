-- ClickHouse 26.7: EXPLAIN ANALYZE Test
-- New Feature: EXPLAIN ANALYZE runs the query and annotates every plan node with
--              measured rows, bytes, time share and parallelism.
-- Reference: https://clickhouse.com/docs/whats-new/changelog (26.7, #106586, #110668)

-- Note: EXPLAIN ANALYZE EXECUTES the query. It is not a dry run — the numbers are real,
-- which is exactly why they are trustworthy, and why you should not point it at a
-- statement with side effects.

-- ============================================
-- 1. Test Data
-- ============================================

SELECT '========== 1. Creating Test Tables ==========';

DROP TABLE IF EXISTS page_views;
DROP TABLE IF EXISTS pages;

CREATE TABLE page_views
(
    view_id    UInt64,
    page_id    UInt32,
    user_id    UInt32,
    ts         DateTime,
    duration_s UInt32
)
ENGINE = MergeTree
ORDER BY view_id;

CREATE TABLE pages
(
    page_id  UInt32,
    title    String,
    category LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY page_id;

INSERT INTO page_views
SELECT
    number,
    number % 500,
    number % 20000,
    toDateTime('2026-07-22 00:00:00') + intDiv(number, 20),
    number % 300
FROM numbers(2000000);

INSERT INTO pages
SELECT
    number,
    concat('Page ', toString(number)),
    ['docs', 'blog', 'product', 'support'][number % 4 + 1]
FROM numbers(500);

SELECT count() AS views FROM page_views;
SELECT count() AS pages FROM pages;

-- ============================================
-- 2. EXPLAIN vs EXPLAIN ANALYZE
-- ============================================

SELECT '========== 2. Plan Only (EXPLAIN) ==========';

-- The estimated shape of the query: node names, no measurements.
EXPLAIN SELECT page_id, count() FROM page_views GROUP BY page_id;

SELECT '========== 2b. Measured (EXPLAIN ANALYZE) ==========';

-- The same plan, executed, with per-node counters attached.
EXPLAIN ANALYZE SELECT page_id, count() FROM page_views GROUP BY page_id;

-- ============================================
-- 3. Reading the Query Summary
-- ============================================

SELECT '========== 3. Planning vs Execution Time ==========';

-- The summary header splits total time into planning and execution and reports the
-- rows/bytes actually read plus peak memory. A large planning share on a small query
-- usually means the plan itself is the problem, not the data volume.
EXPLAIN ANALYZE
SELECT category, count() AS views, avg(duration_s) AS avg_duration
FROM page_views AS v
INNER JOIN pages AS p ON v.page_id = p.page_id
GROUP BY category
ORDER BY views DESC;

-- ============================================
-- 4. Selectivity Per Node
-- ============================================

SELECT '========== 4. Rows In -> Rows Out Per Node ==========';

-- Each node prints "rows N → M (P%)". Following that chain from the bottom up shows
-- where the data volume actually collapses.
EXPLAIN ANALYZE
SELECT count()
FROM page_views
WHERE duration_s > 290 AND user_id % 7 = 0;

-- ============================================
-- 5. Index Usage on a Selective Filter
-- ============================================

SELECT '========== 5. Primary Key Pruning ==========';

-- A predicate on the ORDER BY key prunes granules; the ReadFromMergeTree node reports
-- how many of them survived.
EXPLAIN ANALYZE
SELECT count(), max(duration_s)
FROM page_views
WHERE view_id BETWEEN 1000000 AND 1001000;

SELECT '========== 5b. Same Query Without Key Support ==========';

-- Same row count in the result, but the filter is on a non-key column, so every granule
-- must be read. Compare the ReadFromMergeTree I/O line against the previous query.
EXPLAIN ANALYZE
SELECT count(), max(duration_s)
FROM page_views
WHERE user_id BETWEEN 1000 AND 1001;

-- ============================================
-- 6. Join Internals
-- ============================================

SELECT '========== 6. Join Algorithm, Build and Probe ==========';

-- The Join node names the algorithm, shows which side was built into the hash table,
-- and times the build and probe stages separately.
EXPLAIN ANALYZE
SELECT p.title, count() AS views
FROM page_views AS v
INNER JOIN pages AS p ON v.page_id = p.page_id
WHERE p.category = 'docs'
GROUP BY p.title
ORDER BY views DESC
LIMIT 5;

-- ============================================
-- 7. Finding the Bottleneck by Time Share
-- ============================================

SELECT '========== 7. High-Cardinality GROUP BY ==========';

-- Grouping on 20k distinct users moves the cost into the aggregation stages; the
-- per-stage percentages make that visible without guessing.
EXPLAIN ANALYZE
SELECT user_id, count() AS views, sum(duration_s) AS total
FROM page_views
GROUP BY user_id
ORDER BY total DESC
LIMIT 10;

-- ============================================
-- 8. Comparing Two Formulations of One Question
-- ============================================

SELECT '========== 8. Filter Early vs Filter Late ==========';

-- Filtering inside the subquery.
EXPLAIN ANALYZE
SELECT page_id, cnt
FROM
(
    SELECT page_id, count() AS cnt
    FROM page_views
    WHERE duration_s > 250
    GROUP BY page_id
)
ORDER BY cnt DESC
LIMIT 5;

-- Aggregating everything first, then filtering the result.
EXPLAIN ANALYZE
SELECT page_id, cnt
FROM
(
    SELECT page_id, countIf(duration_s > 250) AS cnt
    FROM page_views
    GROUP BY page_id
)
WHERE cnt > 0
ORDER BY cnt DESC
LIMIT 5;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS page_views;
-- DROP TABLE IF EXISTS pages;

SELECT '========== Test Complete ==========';
SELECT 'EXPLAIN ANALYZE replaces guesswork about a plan with measurements from running it.' AS summary;
