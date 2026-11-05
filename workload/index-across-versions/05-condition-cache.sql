-- settings: use_query_condition_cache, query_condition_cache_store_conditions_as_plaintext, use_query_condition_cache_for_top_k
-- The query condition cache (25.3 setting, default on from 25.4). 8,192,000 rows, ORDER BY id. The point is read_rows of the second run, not the count.
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more, ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.qc;

DROP TABLE IF EXISTS index_lab.qu;

CREATE TABLE index_lab.qc (id UInt64 CODEC(LZ4), v UInt32 CODEC(LZ4)) ENGINE = MergeTree ORDER BY id;

INSERT INTO index_lab.qc SELECT number, intHash32(number) % 1000000 FROM numbers(8192000);

OPTIMIZE TABLE index_lab.qc FINAL;

-- probe: 05-default-1
-- Correct: data-dependent (about 8); the point is read_rows
SELECT count() FROM index_lab.qc WHERE v = 7;

-- probe: 05-default-2
-- Correct: same count as 05-default-1; read_rows should drop where the cache is on by default
SELECT count() FROM index_lab.qc WHERE v = 7;

-- probe: 05-off-2
-- Correct: same count
SELECT count() FROM index_lab.qc WHERE v = 7 SETTINGS use_query_condition_cache = 0;

-- probe: 05-on-1
-- Correct: data-dependent (about 8)
SELECT count() FROM index_lab.qc WHERE v = 8 SETTINGS use_query_condition_cache = 1;

-- probe: 05-on-2
-- Correct: same count as 05-on-1 (25.3: the cache exists, default off)
SELECT count() FROM index_lab.qc WHERE v = 8 SETTINGS use_query_condition_cache = 1;

-- probe: 05-entries value
-- Entries in the cache (data-dependent; 24.8 has no such table).
SELECT count() FROM system.query_condition_cache;

INSERT INTO index_lab.qc SELECT 10000000 + number, 7 FROM numbers(1000);

-- probe: 05-after-insert
-- Correct: 05-default-1 count + 1,000 (new rows are in a new part, not covered by the cached entries)
SELECT count() FROM index_lab.qc WHERE v = 7;

-- Last in the file: lightweight UPDATE (25.7+; earlier builds fail at the table or UPDATE and the probes are skipped).
CREATE TABLE index_lab.qu (id UInt64 CODEC(LZ4), v UInt32 CODEC(LZ4)) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO index_lab.qu SELECT number, intHash32(number) % 1000000 FROM numbers(8192000);

OPTIMIZE TABLE index_lab.qu FINAL;

-- probe: 05-u-check value
-- Correct: 1 (v of id 100 is not 7 before the UPDATE; if 0, pick another id).
SELECT v != 7 FROM index_lab.qu WHERE id = 100;

-- probe: 05-u-1
-- Correct: data-dependent (about 8)
SELECT count() FROM index_lab.qu WHERE v = 7;

UPDATE index_lab.qu SET v = 7 WHERE id = 100;

-- probe: 05-u-2
-- Correct: 05-u-1 count + 1 (25.11 changelog #90204 fixed wrong results after lightweight updates with the cache)
SELECT count() FROM index_lab.qu WHERE v = 7;
