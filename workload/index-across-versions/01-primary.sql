-- settings: use_primary_key, force_primary_key, index_granularity, index_granularity_bytes, use_lightweight_primary_key_index_analysis
-- Primary index and ORDER BY prefix on 8,192,000 rows = 1,000 granules (index_granularity 8192), one part per table (OPTIMIZE ... FINAL).
-- Each count probe is paired with a -g probe that prints the EXPLAIN indexes = 1 granule lines.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.pk_lo;

DROP TABLE IF EXISTS index_lab.pk_hi;

DROP TABLE IF EXISTS index_lab.pk_ts;

CREATE TABLE index_lab.pk_lo (a UInt8, b UInt64, c UInt32, ts DateTime) ENGINE = MergeTree ORDER BY (a, b);

CREATE TABLE index_lab.pk_hi (a UInt32, b UInt64, c UInt32, ts DateTime) ENGINE = MergeTree ORDER BY (a, b);

CREATE TABLE index_lab.pk_ts (ts DateTime, v UInt64) ENGINE = MergeTree ORDER BY ts;

INSERT INTO index_lab.pk_lo SELECT number % 10, number, intHash32(number) % 1000000, toDateTime('2026-01-01 00:00:00') + number FROM numbers(8192000);

INSERT INTO index_lab.pk_hi SELECT number % 100000, number, intHash32(number) % 1000000, toDateTime('2026-01-01 00:00:00') + number FROM numbers(8192000);

INSERT INTO index_lab.pk_ts SELECT toDateTime('2026-01-01 00:00:00') + number, number FROM numbers(8192000);

OPTIMIZE TABLE index_lab.pk_lo FINAL;

OPTIMIZE TABLE index_lab.pk_hi FINAL;

OPTIMIZE TABLE index_lab.pk_ts FINAL;

-- probe: 01-a-eq value
-- Correct: 819,200
SELECT count() FROM index_lab.pk_lo WHERE a = 3;

-- probe: 01-a-eq-g value
-- Granules read for 01-a-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE a = 3))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-b-lo value
-- Correct: 1 (second key column only, low-cardinality first column)
SELECT count() FROM index_lab.pk_lo WHERE b = 5000003;

-- probe: 01-b-lo-g value
-- Granules read for 01-b-lo (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE b = 5000003))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-b-hi value
-- Correct: 1 (second key column only, high-cardinality first column)
SELECT count() FROM index_lab.pk_hi WHERE b = 5000003;

-- probe: 01-b-hi-g value
-- Granules read for 01-b-hi (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_hi WHERE b = 5000003))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-ab value
-- Correct: 1
SELECT count() FROM index_lab.pk_lo WHERE a = 3 AND b = 5000003;

-- probe: 01-ab-g value
-- Granules read for 01-ab (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE a = 3 AND b = 5000003))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-a-in value
-- Correct: 1,638,400
SELECT count() FROM index_lab.pk_lo WHERE a IN (3, 7);

-- probe: 01-a-in-g value
-- Granules read for 01-a-in (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE a IN (3, 7)))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-c value
-- Correct: data-dependent (non-key column)
SELECT count() FROM index_lab.pk_lo WHERE c = 7;

-- probe: 01-c-g value
-- Granules read for 01-c (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE c = 7))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-ts-range value
-- Correct: 86,400
SELECT count() FROM index_lab.pk_ts WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00';

-- probe: 01-ts-range-g value
-- Granules read for 01-ts-range (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_ts WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-ts-todate value
-- Correct: 86,400 (monotonic function of the key)
SELECT count() FROM index_lab.pk_ts WHERE toDate(ts) = '2026-02-01';

-- probe: 01-ts-todate-g value
-- Granules read for 01-ts-todate (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_ts WHERE toDate(ts) = '2026-02-01'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-ts-tohour value
-- Correct: data-dependent (non-monotonic function of the key)
SELECT count() FROM index_lab.pk_ts WHERE toHour(ts) = 3;

-- probe: 01-ts-tohour-g value
-- Granules read for 01-ts-tohour (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_ts WHERE toHour(ts) = 3))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 01-explain show
-- Plain EXPLAIN indexes = 1 for a filter on the second key column only.
EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE b = 5000003;

-- Last in the file: 26.1+ only (earlier builds reject use_primary_key = 0 with code 115).
-- use_query_condition_cache = 0: the cache already holds `a = 3` from 01-a-eq and would hide the full read (827,392 rows instead of 8,192,000).
-- probe: 01-nopk value
-- Correct: 819,200
SELECT count() FROM index_lab.pk_lo WHERE a = 3 SETTINGS use_primary_key = 0, use_query_condition_cache = 0;

-- probe: 01-nopk-g value
-- Granules read for 01-nopk (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.pk_lo WHERE a = 3 SETTINGS use_primary_key = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';
