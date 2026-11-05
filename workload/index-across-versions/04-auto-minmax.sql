-- settings: add_minmax_index_for_numeric_columns, add_minmax_index_for_string_columns, add_minmax_index_for_temporal_columns
-- Automatic minmax indices (25.1 changelog; 24.8 fails at CREATE and every probe is skipped). 8,192,000 rows, ORDER BY id.
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more, ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.am;

DROP TABLE IF EXISTS index_lab.am_off;

DROP TABLE IF EXISTS index_lab.am_t;

CREATE TABLE index_lab.am_off
(
    id UInt64 CODEC(LZ4),
    v UInt32 CODEC(LZ4),
    s String CODEC(LZ4),
    ts DateTime CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY id;

CREATE TABLE index_lab.am
(
    id UInt64 CODEC(LZ4),
    v UInt32 CODEC(LZ4),
    s String CODEC(LZ4),
    ts DateTime CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY id
SETTINGS add_minmax_index_for_numeric_columns = 1, add_minmax_index_for_string_columns = 1;

INSERT INTO index_lab.am_off SELECT number, intDiv(number, 10), leftPad(toString(intDiv(number, 1000)), 6, '0'), toDateTime('2026-01-01 00:00:00') + number FROM numbers(8192000);

OPTIMIZE TABLE index_lab.am_off FINAL;

INSERT INTO index_lab.am SELECT number, intDiv(number, 10), leftPad(toString(intDiv(number, 1000)), 6, '0'), toDateTime('2026-01-01 00:00:00') + number FROM numbers(8192000);

OPTIMIZE TABLE index_lab.am FINAL;

-- probe: 04-indices value
-- Names of the automatic indices on am (data-dependent).
SELECT arrayStringConcat(groupArray(name), ', ') FROM (SELECT name FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'am' ORDER BY name);

-- probe: 04-v-on value
-- Correct: 10,000
SELECT count() FROM index_lab.am WHERE v BETWEEN 400000 AND 400999;

-- probe: 04-v-on-g value
-- Granules read for 04-v-on (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am WHERE v BETWEEN 400000 AND 400999))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 04-v-off value
-- Correct: 10,000
SELECT count() FROM index_lab.am_off WHERE v BETWEEN 400000 AND 400999;

-- probe: 04-v-off-g value
-- Granules read for 04-v-off (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am_off WHERE v BETWEEN 400000 AND 400999))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 04-s-on value
-- Correct: 1,000
SELECT count() FROM index_lab.am WHERE s = '004000';

-- probe: 04-s-on-g value
-- Granules read for 04-s-on (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am WHERE s = '004000'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 04-s-off value
-- Correct: 1,000
SELECT count() FROM index_lab.am_off WHERE s = '004000';

-- probe: 04-s-off-g value
-- Granules read for 04-s-off (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am_off WHERE s = '004000'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 04-ts-on value
-- Correct: 86,400 (is DateTime covered by the numeric setting?)
SELECT count() FROM index_lab.am WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00';

-- probe: 04-ts-on-g value
-- Granules read for 04-ts-on (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- Last in the file: add_minmax_index_for_temporal_columns exists on 26.3+ only (25.3 and 25.8 fail here).
CREATE TABLE index_lab.am_t
(
    id UInt64 CODEC(LZ4),
    v UInt32 CODEC(LZ4),
    s String CODEC(LZ4),
    ts DateTime CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY id
SETTINGS add_minmax_index_for_temporal_columns = 1;

INSERT INTO index_lab.am_t SELECT number, intDiv(number, 10), leftPad(toString(intDiv(number, 1000)), 6, '0'), toDateTime('2026-01-01 00:00:00') + number FROM numbers(8192000);

OPTIMIZE TABLE index_lab.am_t FINAL;

-- probe: 04-indices-t value
-- Names of the automatic indices on am_t (data-dependent).
SELECT arrayStringConcat(groupArray(name), ', ') FROM (SELECT name FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'am_t' ORDER BY name);

-- probe: 04-ts-t value
-- Correct: 86,400
SELECT count() FROM index_lab.am_t WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00';

-- probe: 04-ts-t-g value
-- Granules read for 04-ts-t (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.am_t WHERE ts >= '2026-02-01 00:00:00' AND ts < '2026-02-02 00:00:00'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';
