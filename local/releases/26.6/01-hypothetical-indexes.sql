-- ClickHouse 26.6: Hypothetical Indexes + EXPLAIN WHATIF Test
-- New Feature: CREATE HYPOTHETICAL INDEX registers an index candidate without building it,
--              and EXPLAIN WHATIF estimates how much data it would skip.
-- Reference: https://clickhouse.com/blog/clickhouse-release-26-06

-- Note: hypothetical indexes are SESSION-SCOPED. They exist only inside the connection
-- that created them, are never written to disk, and never touch the table's metadata.
-- That is why this whole file must run in a single clickhouse-client session.

-- ============================================
-- 1. Test Data — Three Different Data Shapes
-- ============================================

SELECT '========== 1. Creating Test Table (1M rows) ==========';

DROP TABLE IF EXISTS web_events;

CREATE TABLE web_events
(
    event_id    UInt64,
    ts          DateTime,
    region      LowCardinality(String),
    status      String,
    duration_ms UInt32
)
ENGINE = MergeTree
ORDER BY event_id;

-- Deliberately three different distributions, so each index type has a clear winner/loser:
--   region      -> perfectly clustered (one region per block of 125k rows)
--   status      -> 'error' clustered in a narrow id range, 'timeout' spread uniformly
--   duration_ms -> monotonically correlated with the ORDER BY key
INSERT INTO web_events
SELECT
    number AS event_id,
    toDateTime('2026-06-25 00:00:00') + intDiv(number, 100) AS ts,
    ['us-east', 'us-west', 'eu-west', 'eu-central',
     'ap-south', 'ap-north', 'sa-east', 'af-south'][intDiv(number, 125000) + 1] AS region,
    multiIf(number BETWEEN 700000 AND 700500, 'error',
            number % 1000 = 0,                'timeout',
                                              'ok') AS status,
    number AS duration_ms
FROM numbers(1000000);

SELECT count() AS rows, uniqExact(region) AS regions, uniqExact(status) AS statuses
FROM web_events;

-- ============================================
-- 2. EXPLAIN WHATIF Before Defining Anything
-- ============================================

SELECT '========== 2. WHATIF With No Candidate Defined ==========';

-- WHATIF always prints the baseline first: what the query already reads after
-- primary key / partition pruning and existing indexes.
EXPLAIN WHATIF SELECT count() FROM web_events WHERE region = 'eu-west';

-- ============================================
-- 3. First Candidate — set Index on a Clustered Column
-- ============================================

SELECT '========== 3. Hypothetical set() Index on region ==========';

CREATE HYPOTHETICAL INDEX idx_region ON web_events (region) TYPE set(4) GRANULARITY 1;

-- Nothing was built, nothing was written. Only an estimate is produced.
EXPLAIN WHATIF SELECT count() FROM web_events WHERE region = 'eu-west';

-- ============================================
-- 4. Several Candidates Compared in One Shot
-- ============================================

SELECT '========== 4. Three Candidates, One WHATIF ==========';

CREATE HYPOTHETICAL INDEX idx_duration ON web_events (duration_ms) TYPE minmax GRANULARITY 4;
CREATE HYPOTHETICAL INDEX idx_status   ON web_events (status)      TYPE bloom_filter(0.01) GRANULARITY 1;

-- Every applicable candidate is reported for the same query, so candidates can be
-- ranked against each other instead of being benchmarked one build at a time.
EXPLAIN WHATIF SELECT count() FROM web_events WHERE duration_ms BETWEEN 900000 AND 900500;

-- ============================================
-- 5. Candidate Inventory
-- ============================================

SELECT '========== 5. system.hypothetical_indexes ==========';

SELECT database, table, name, type, type_full, expression, granularity
FROM system.hypothetical_indexes
ORDER BY name;

-- ============================================
-- 6. Clustered vs Uniformly Spread Values
-- ============================================

SELECT '========== 6. Why Distribution Decides the Win ==========';

-- 'error' lives in a narrow event_id range -> most granules can be skipped.
SELECT 'status = error (clustered, 501 rows)' AS scenario;
EXPLAIN WHATIF SELECT count() FROM web_events WHERE status = 'error';

-- 'timeout' appears every 1000 rows -> every granule holds one, so nothing can be skipped
-- even though the value is just as rare. Rarity alone does not make an index useful.
SELECT 'status = timeout (uniformly spread, 1000 rows)' AS scenario;
EXPLAIN WHATIF SELECT count() FROM web_events WHERE status = 'timeout';

-- ============================================
-- 7. Non-Applicable Candidates
-- ============================================

SELECT '========== 7. Mixed Verdicts in One Report ==========';

-- A minmax index on duration_ms says nothing about a region predicate: WHATIF reports
-- 'not_applicable' with the reason rather than silently omitting it.
EXPLAIN WHATIF SELECT count() FROM web_events WHERE region = 'ap-south';

-- ============================================
-- 8. Dropping a Candidate
-- ============================================

SELECT '========== 8. DROP HYPOTHETICAL INDEX ==========';

DROP HYPOTHETICAL INDEX idx_status ON web_events;

SELECT name, type_full FROM system.hypothetical_indexes ORDER BY name;

-- ============================================
-- 9. The Table Was Never Modified
-- ============================================

SELECT '========== 9. Table Metadata Is Untouched ==========';

-- No index definition in the DDL...
SHOW CREATE TABLE web_events;

-- ...and nothing in the real skip-index catalogue either.
SELECT count() AS real_indexes
FROM system.data_skipping_indices
WHERE table = 'web_events';

-- ============================================
-- 10. Materialize the Winner and Confirm the Estimate
-- ============================================

SELECT '========== 10. Build the Winner for Real ==========';

ALTER TABLE web_events ADD INDEX idx_region_real region TYPE set(4) GRANULARITY 1;
ALTER TABLE web_events MATERIALIZE INDEX idx_region_real SETTINGS mutations_sync = 2;

SELECT name, type_full, expr, granularity FROM system.data_skipping_indices WHERE table = 'web_events';

-- The Granules line should match the mark count WHATIF predicted in step 3.
EXPLAIN indexes = 1 SELECT count() FROM web_events WHERE region = 'eu-west';

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS web_events;

SELECT '========== Test Complete ==========';
SELECT 'EXPLAIN WHATIF prices an index candidate before you pay to build it.' AS summary;
