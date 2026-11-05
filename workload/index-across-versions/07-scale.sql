-- settings: use_skip_indexes, use_query_condition_cache, default_compression_codec
-- Timings at 20,000,000 rows (min of 5). The cell is median (min) and memory; the rows table gives read_rows.
-- The -nc twins add use_query_condition_cache = 0 (the setting does not exist on 24.8, so they fail there with code 115).
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more, ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.big;

CREATE TABLE index_lab.big
(
    id UInt64 CODEC(LZ4),
    uid UInt64 CODEC(LZ4),
    v UInt32 CODEC(LZ4),
    msg String CODEC(LZ4),
    INDEX i_uid uid TYPE bloom_filter GRANULARITY 1,
    INDEX i_tok msg TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO index_lab.big SELECT number, intHash64(number), intHash32(number) % 1000000, concat('GET /api/v1/item/', toString(number % 1000), ' status=', if(number % 1000003 = 0, '504 timeout', '200 ok'), ' user=u', toString(number % 100000)) FROM numbers(20000000);

OPTIMIZE TABLE index_lab.big FINAL;

-- probe: 07-id repeat=5
-- Correct: 1
SELECT count() FROM index_lab.big WHERE id = 12345678;

-- probe: 07-uid repeat=5
-- Correct: 1
SELECT count() FROM index_lab.big WHERE uid = intHash64(12345678);

-- probe: 07-uid-noidx repeat=5
-- Correct: 1 (use_skip_indexes = 0)
SELECT count() FROM index_lab.big WHERE uid = intHash64(12345678) SETTINGS use_skip_indexes = 0;

-- probe: 07-tok repeat=5
-- Correct: 20
SELECT count() FROM index_lab.big WHERE hasToken(msg, 'timeout');

-- probe: 07-tok-noidx repeat=5
-- Correct: 20 (use_skip_indexes = 0)
SELECT count() FROM index_lab.big WHERE hasToken(msg, 'timeout') SETTINGS use_skip_indexes = 0;

-- probe: 07-v repeat=5
-- Correct: data-dependent (no index)
SELECT count() FROM index_lab.big WHERE v = 7;

-- probe: 07-uid-nc repeat=5
-- Correct: 1
SELECT count() FROM index_lab.big WHERE uid = intHash64(12345678) SETTINGS use_query_condition_cache = 0;

-- probe: 07-uid-noidx-nc repeat=5
-- Correct: 1 (use_skip_indexes = 0)
SELECT count() FROM index_lab.big WHERE uid = intHash64(12345678) SETTINGS use_skip_indexes = 0, use_query_condition_cache = 0;

-- probe: 07-tok-nc repeat=5
-- Correct: 20
SELECT count() FROM index_lab.big WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

-- probe: 07-tok-noidx-nc repeat=5
-- Correct: 20 (use_skip_indexes = 0)
SELECT count() FROM index_lab.big WHERE hasToken(msg, 'timeout') SETTINGS use_skip_indexes = 0, use_query_condition_cache = 0;

-- probe: 07-v-nc repeat=5
-- Correct: data-dependent (no index)
SELECT count() FROM index_lab.big WHERE v = 7 SETTINGS use_query_condition_cache = 0;

-- probe: 07-codec show
-- The part default codec and the declared column codec of big on this build (the column codec is what the data is written with).
SELECT
    (SELECT groupUniqArray(default_compression_codec) FROM system.parts WHERE database = 'index_lab' AND table = 'big' AND active) AS part_default,
    (SELECT groupUniqArray(compression_codec) FROM system.columns WHERE database = 'index_lab' AND table = 'big') AS column_codec;

-- probe: 07-sizes value
-- Compressed bytes per skip index (data-dependent).
SELECT arrayStringConcat(groupArray(concat(name, '=', toString(data_compressed_bytes))), ', ') FROM (SELECT name, data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'big' ORDER BY name);

-- Control for the skip index files' codec (last in the file: 24.8 has no `default_compression_codec` table setting and only these probes skip).
-- CODEC(LZ4) on the columns does not reach the skip index files: on 26.9+ they take the size-aware default (ZSTD(3) for this part).
-- big_lz4 is big with the table default pinned to LZ4 as well.

DROP TABLE IF EXISTS index_lab.big_lz4;

CREATE TABLE index_lab.big_lz4
(
    id UInt64 CODEC(LZ4),
    uid UInt64 CODEC(LZ4),
    v UInt32 CODEC(LZ4),
    msg String CODEC(LZ4),
    INDEX i_uid uid TYPE bloom_filter GRANULARITY 1,
    INDEX i_tok msg TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
)
ENGINE = MergeTree
ORDER BY id
SETTINGS default_compression_codec = 'LZ4';

INSERT INTO index_lab.big_lz4 SELECT * FROM index_lab.big;

OPTIMIZE TABLE index_lab.big_lz4 FINAL;

-- probe: 07-lz4-uid-nc repeat=5
-- Correct: 1 (bloom_filter, cache off, table default LZ4)
SELECT count() FROM index_lab.big_lz4 WHERE uid = intHash64(12345678) SETTINGS use_query_condition_cache = 0;

-- probe: 07-lz4-tok-nc repeat=5
-- Correct: 20 (tokenbf_v1, cache off, table default LZ4)
SELECT count() FROM index_lab.big_lz4 WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

-- probe: 07-lz4-codec value
-- The part default codec of big_lz4 (LZ4 expected on every build that accepts the setting).
SELECT groupUniqArray(default_compression_codec) FROM system.parts WHERE database = 'index_lab' AND table = 'big_lz4' AND active;

-- probe: 07-lz4-sizes value
-- Compressed bytes per skip index of big_lz4 (data-dependent).
SELECT arrayStringConcat(groupArray(concat(name, '=', toString(data_compressed_bytes))), ', ') FROM (SELECT name, data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'big_lz4' ORDER BY name);
