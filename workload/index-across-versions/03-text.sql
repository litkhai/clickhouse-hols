-- settings: enable_full_text_index, allow_experimental_full_text_index, query_plan_direct_read_from_text_index, query_plan_optimize_count_from_text_index, query_plan_text_index_add_hint, text_index_like_min_pattern_length, use_text_index_like_evaluation_by_dictionary_scan, text_index_posting_list_apply_mode, use_query_condition_cache
-- The text index (26.3+ syntax; 24.8-25.8 fail at CREATE and every probe is skipped). 20,000,000 rows, ORDER BY id, one part.
-- 'timeout' and '504' appear only where number % 1000003 = 0: 20 rows (0, 1000003, ..., 19 * 1000003).
-- Timing probes carry use_query_condition_cache = 0 (the cache would make repeats 2-5 cheaper).
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more, ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.tx;

CREATE TABLE index_lab.tx
(
    id UInt64 CODEC(LZ4),
    msg String CODEC(LZ4),
    INDEX i_msg msg TYPE text(tokenizer = splitByNonAlpha)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO index_lab.tx SELECT number, concat('GET /api/v1/item/', toString(number % 1000), ' status=', if(number % 1000003 = 0, '504 timeout', '200 ok'), ' user=u', toString(number % 100000)) FROM numbers(20000000);

OPTIMIZE TABLE index_lab.tx FINAL;

-- probe: 03-index value
-- The type and the default granularity of the text index (no GRANULARITY clause was written).
SELECT type_full, granularity FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'tx';

-- probe: 03-size value
-- Compressed bytes of the index and of the whole part (data-dependent).
SELECT (SELECT data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'tx'), (SELECT sum(data_compressed_bytes) FROM system.parts WHERE database = 'index_lab' AND table = 'tx' AND active);

-- probe: 03-token repeat=5 value
-- Correct: 20
SELECT count() FROM index_lab.tx WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

-- probe: 03-token-g value
-- Granules read for 03-token (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.tx WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 03-any repeat=5 value
-- Correct: 20
SELECT count() FROM index_lab.tx WHERE hasAnyTokens(msg, ['timeout', 'nosuchtoken']) SETTINGS use_query_condition_cache = 0;

-- probe: 03-all repeat=5 value
-- Correct: 20
SELECT count() FROM index_lab.tx WHERE hasAllTokens(msg, ['timeout', '504']) SETTINGS use_query_condition_cache = 0;

-- probe: 03-like repeat=5 value
-- Correct: 20
SELECT count() FROM index_lab.tx WHERE msg LIKE '%timeout%' SETTINGS use_query_condition_cache = 0;

-- probe: 03-like-g value
-- Granules read for 03-like (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.tx WHERE msg LIKE '%timeout%' SETTINGS use_query_condition_cache = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 03-like-sub repeat=5 value
-- Correct: 20
SELECT count() FROM index_lab.tx WHERE msg LIKE '%imeou%' SETTINGS use_query_condition_cache = 0;

-- probe: 03-like-sub-g value
-- Granules read for 03-like-sub (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.tx WHERE msg LIKE '%imeou%' SETTINGS use_query_condition_cache = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 03-eq repeat=5 value
-- Correct: 1
SELECT count() FROM index_lab.tx WHERE msg = 'GET /api/v1/item/0 status=504 timeout user=u0' SETTINGS use_query_condition_cache = 0;

-- probe: 03-eq-g value
-- Granules read for 03-eq (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.tx WHERE msg = 'GET /api/v1/item/0 status=504 timeout user=u0' SETTINGS use_query_condition_cache = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 03-not repeat=5 value
-- Correct: 19,999,980
SELECT count() FROM index_lab.tx WHERE NOT hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

-- probe: 03-not-g value
-- Granules read for 03-not (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.tx WHERE NOT hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 03-frequent repeat=5 value
-- Correct: 19,999,980
SELECT count() FROM index_lab.tx WHERE hasToken(msg, 'ok') SETTINGS use_query_condition_cache = 0;

-- probe: 03-sum repeat=5 value
-- Correct: 190,000,570 (sum of 0, 1000003, ..., 19 * 1000003)
SELECT sum(id) FROM index_lab.tx WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

-- probe: 03-noindex repeat=5 value
-- Correct: 20 (control, no skip index)
SELECT count() FROM index_lab.tx WHERE hasToken(msg, 'timeout') SETTINGS use_skip_indexes = 0, use_query_condition_cache = 0;

-- probe: 03-nodirect repeat=5 value
-- Correct: 20 (direct read from the text index off)
SELECT count() FROM index_lab.tx WHERE hasToken(msg, 'timeout') SETTINGS query_plan_direct_read_from_text_index = 0, use_query_condition_cache = 0;

-- Posting-list codecs (last in the file: a build without the parameter fails at CREATE and only these probes skip).
-- The default `text_index_posting_list_codec` is `none` (26.8, 26.10); `bitpacking` and `pfor` are per-index parameters
-- (26.10 changelog #118123 adds `pfor`). Same data as `tx`.

DROP TABLE IF EXISTS index_lab.tx_bp;

DROP TABLE IF EXISTS index_lab.tx_pfor;

CREATE TABLE index_lab.tx_bp
(
    id UInt64 CODEC(LZ4),
    msg String CODEC(LZ4),
    INDEX i_msg msg TYPE text(tokenizer = splitByNonAlpha, posting_list_codec = 'bitpacking')
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO index_lab.tx_bp SELECT * FROM index_lab.tx;

OPTIMIZE TABLE index_lab.tx_bp FINAL;

-- probe: 03-size-bitpacking value
-- Compressed bytes of the text index with posting_list_codec = 'bitpacking' (data-dependent).
SELECT data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'tx_bp';

-- probe: 03-token-bitpacking repeat=5 value
-- Correct: 1 / 20
SELECT sum(id) > 0, count() FROM index_lab.tx_bp WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;

CREATE TABLE index_lab.tx_pfor
(
    id UInt64 CODEC(LZ4),
    msg String CODEC(LZ4),
    INDEX i_msg msg TYPE text(tokenizer = splitByNonAlpha, posting_list_codec = 'pfor')
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO index_lab.tx_pfor SELECT * FROM index_lab.tx;

OPTIMIZE TABLE index_lab.tx_pfor FINAL;

-- probe: 03-size-pfor value
-- Compressed bytes of the text index with posting_list_codec = 'pfor' (data-dependent).
SELECT data_compressed_bytes FROM system.data_skipping_indices WHERE database = 'index_lab' AND table = 'tx_pfor';

-- probe: 03-token-pfor repeat=5 value
-- Correct: 1 / 20
SELECT sum(id) > 0, count() FROM index_lab.tx_pfor WHERE hasToken(msg, 'timeout') SETTINGS use_query_condition_cache = 0;
