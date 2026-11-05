-- settings: use_skip_indexes, use_skip_indexes_on_data_read, use_skip_indexes_for_disjunctions, secondary_indices_enable_bulk_filtering, packed_skip_index_max_bytes
-- Skip index types on non-key columns: 8,192,000 rows (1,000 granules), ORDER BY id, one part.
-- Message rows: 'timeout' and '504' appear only where number % 1000003 = 0, i.e. 9 rows (0, 1000003, ..., 8000024).
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more, ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.sk;

CREATE TABLE index_lab.sk
(
    id UInt64 CODEC(LZ4),
    t_corr UInt32 CODEC(LZ4),
    v_rand UInt32 CODEC(LZ4),
    cat String CODEC(LZ4),
    many UInt32 CODEC(LZ4),
    many0 UInt32 CODEC(LZ4),
    uid UInt64 CODEC(LZ4),
    uid4 UInt64 CODEC(LZ4),
    msg_t String CODEC(LZ4),
    msg_s String CODEC(LZ4),
    msg_n String CODEC(LZ4),
    INDEX i_corr t_corr TYPE minmax GRANULARITY 1,
    INDEX i_rand v_rand TYPE minmax GRANULARITY 1,
    INDEX i_cat cat TYPE set(100) GRANULARITY 1,
    INDEX i_many many TYPE set(100) GRANULARITY 1,
    INDEX i_many0 many0 TYPE set(0) GRANULARITY 1,
    INDEX i_uid uid TYPE bloom_filter GRANULARITY 1,
    INDEX i_uid4 uid4 TYPE bloom_filter GRANULARITY 4,
    INDEX i_tok msg_t TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1,
    INDEX i_tok_small msg_s TYPE tokenbf_v1(1024, 2, 0) GRANULARITY 1,
    INDEX i_ngr msg_n TYPE ngrambf_v1(4, 32768, 3, 0) GRANULARITY 1
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO index_lab.sk SELECT number, intDiv(number, 10), intHash32(number) % 1000000,
    if(number >= 4096000 AND number < 4097000, 'rare', concat('c', toString(number % 50))),
    intHash32(number + 1) % 100000, intHash32(number + 1) % 100000, intHash64(number), intHash64(number),
    concat('GET /api/v1/item/', toString(number % 1000), ' status=', if(number % 1000003 = 0, '504 timeout', '200 ok'), ' user=u', toString(number % 100000)), concat('GET /api/v1/item/', toString(number % 1000), ' status=', if(number % 1000003 = 0, '504 timeout', '200 ok'), ' user=u', toString(number % 100000)), concat('GET /api/v1/item/', toString(number % 1000), ' status=', if(number % 1000003 = 0, '504 timeout', '200 ok'), ' user=u', toString(number % 100000))
FROM numbers(8192000);

OPTIMIZE TABLE index_lab.sk FINAL;

-- probe: 02-corr-eq value
-- Correct: 10
SELECT count() FROM index_lab.sk WHERE t_corr = 400000;

-- probe: 02-corr-eq-g value
-- Granules read for 02-corr-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE t_corr = 400000))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-corr-range value
-- Correct: 10,000
SELECT count() FROM index_lab.sk WHERE t_corr BETWEEN 400000 AND 400999;

-- probe: 02-corr-range-g value
-- Granules read for 02-corr-range (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE t_corr BETWEEN 400000 AND 400999))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-rand-eq value
-- Correct: data-dependent
SELECT count() FROM index_lab.sk WHERE v_rand = 777;

-- probe: 02-rand-eq-g value
-- Granules read for 02-rand-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE v_rand = 777))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-rand-range value
-- Correct: data-dependent
SELECT count() FROM index_lab.sk WHERE v_rand BETWEEN 1000 AND 1999;

-- probe: 02-rand-range-g value
-- Granules read for 02-rand-range (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE v_rand BETWEEN 1000 AND 1999))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-cat-rare value
-- Correct: 1,000
SELECT count() FROM index_lab.sk WHERE cat = 'rare';

-- probe: 02-cat-rare-g value
-- Granules read for 02-cat-rare (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE cat = 'rare'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-cat-none value
-- Correct: 0
SELECT count() FROM index_lab.sk WHERE cat = 'nope';

-- probe: 02-cat-none-g value
-- Granules read for 02-cat-none (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE cat = 'nope'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-many-none value
-- Correct: 0 (set(100) overflows: about 8,000 distinct values per granule)
SELECT count() FROM index_lab.sk WHERE many = 100001;

-- probe: 02-many-none-g value
-- Granules read for 02-many-none (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE many = 100001))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-many0-none value
-- Correct: 0 (set(0) is unlimited)
SELECT count() FROM index_lab.sk WHERE many0 = 100001;

-- probe: 02-many0-none-g value
-- Granules read for 02-many0-none (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE many0 = 100001))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-uid-eq value
-- Correct: 1
SELECT count() FROM index_lab.sk WHERE uid = intHash64(5000003);

-- probe: 02-uid-eq-g value
-- Granules read for 02-uid-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE uid = intHash64(5000003)))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-uid-in value
-- Correct: 3
SELECT count() FROM index_lab.sk WHERE uid IN (intHash64(1), intHash64(2), intHash64(3));

-- probe: 02-uid-in-g value
-- Granules read for 02-uid-in (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE uid IN (intHash64(1), intHash64(2), intHash64(3))))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-uid-ne value
-- Correct: 8,191,999
SELECT count() FROM index_lab.sk WHERE uid != intHash64(5000003);

-- probe: 02-uid-ne-g value
-- Granules read for 02-uid-ne (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE uid != intHash64(5000003)))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-uid4-eq value
-- Correct: 1 (GRANULARITY 4)
SELECT count() FROM index_lab.sk WHERE uid4 = intHash64(5000003);

-- probe: 02-uid4-eq-g value
-- Granules read for 02-uid4-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE uid4 = intHash64(5000003)))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-uid-cast value
-- Correct: 1 (26.10 changelog #120220: indexes used through value-preserving casts)
SELECT count() FROM index_lab.sk WHERE toNullable(uid) = intHash64(5000003);

-- probe: 02-uid-cast-g value
-- Granules read for 02-uid-cast (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE toNullable(uid) = intHash64(5000003)))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-tok-token value
-- Correct: 9
SELECT count() FROM index_lab.sk WHERE hasToken(msg_t, 'timeout');

-- probe: 02-tok-token-g value
-- Granules read for 02-tok-token (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE hasToken(msg_t, 'timeout')))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-tok-like value
-- Correct: 9
SELECT count() FROM index_lab.sk WHERE msg_t LIKE '%timeout%';

-- probe: 02-tok-like-g value
-- Granules read for 02-tok-like (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE msg_t LIKE '%timeout%'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-tok-not value
-- Correct: 8,191,991
SELECT count() FROM index_lab.sk WHERE NOT hasToken(msg_t, 'timeout');

-- probe: 02-tok-not-g value
-- Granules read for 02-tok-not (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE NOT hasToken(msg_t, 'timeout')))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-toksmall-token value
-- Correct: 9 (tokenbf_v1(1024, 2, 0), the parameters the old article showed)
SELECT count() FROM index_lab.sk WHERE hasToken(msg_s, 'timeout');

-- probe: 02-toksmall-token-g value
-- Granules read for 02-toksmall-token (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE hasToken(msg_s, 'timeout')))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-ngr-like value
-- Correct: 9
SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%timeout%';

-- probe: 02-ngr-like-g value
-- Granules read for 02-ngr-like (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%timeout%'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-ngr-sub value
-- Correct: 9
SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%imeou%';

-- probe: 02-ngr-sub-g value
-- Granules read for 02-ngr-sub (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%imeou%'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-ngr-short value
-- Correct: 9 (3 chars < n = 4, so the index cannot prune)
SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%eou%';

-- probe: 02-ngr-short-g value
-- Granules read for 02-ngr-short (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE msg_n LIKE '%eou%'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-ngr-token value
-- Correct: 9
SELECT count() FROM index_lab.sk WHERE hasToken(msg_n, 'timeout');

-- probe: 02-ngr-token-g value
-- Granules read for 02-ngr-token (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE hasToken(msg_n, 'timeout')))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-or value
-- Correct: 1,001 (25.12 changelog: skip indexes for OR, use_skip_indexes_for_disjunctions)
SELECT count() FROM index_lab.sk WHERE uid = intHash64(5000003) OR cat = 'rare';

-- probe: 02-or-g value
-- Granules read for 02-or (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.sk WHERE uid = intHash64(5000003) OR cat = 'rare'))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 02-sizes value
-- Compressed bytes per skip index (data-dependent).
SELECT arrayStringConcat(groupArray(concat(name, '=', toString(data_compressed_bytes))), ', ') FROM (SELECT name, data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'sk' ORDER BY name);

-- probe: 02-part value
-- Rows, data bytes, skip-index bytes of the part. Correct rows: 8192000. secondary_indices_compressed_bytes may not exist on 24.8.
SELECT sum(rows), sum(data_compressed_bytes), sum(secondary_indices_compressed_bytes) FROM system.parts WHERE database = 'index_lab' AND table = 'sk' AND active;
