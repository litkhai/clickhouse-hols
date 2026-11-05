-- Read cost of FINAL at 20M rows. Every table is one part (per partition) after OPTIMIZE ... FINAL on the base insert,
-- then merges are stopped, then the re-insert:
--   s_mt     MergeTree, control
--   s_clean  ReplacingMergeTree, no re-insert (one part, no duplicates)
--   s_1p     ReplacingMergeTree, 1% of keys re-inserted (id % 100 = 0, ver 2, v + 1)
--   s_10p    ReplacingMergeTree, 10% of keys re-inserted (id % 10 = 0, ver 2, v + 1)
--   s_part   ReplacingMergeTree PARTITION BY id % 16, 1% re-inserted
-- Every column carries CODEC(LZ4): from 26.9 a part of 100 MB or more defaults to ZSTD(3) (older builds: LZ4), and the
-- 20M-row parts here are about 160 MiB, so without the pin the timings would compare codecs as well as builds.
-- Query shape: SELECT sum(v), count() FROM <t> [FINAL]. Each timing probe runs 5 times.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.s_mt;

DROP TABLE IF EXISTS final_lab.s_clean;

DROP TABLE IF EXISTS final_lab.s_1p;

DROP TABLE IF EXISTS final_lab.s_10p;

DROP TABLE IF EXISTS final_lab.s_part;

CREATE TABLE final_lab.s_mt (id UInt64 CODEC(LZ4), v UInt64 CODEC(LZ4), s String CODEC(LZ4), ver UInt32 CODEC(LZ4)) ENGINE = MergeTree ORDER BY id;

CREATE TABLE final_lab.s_clean (id UInt64 CODEC(LZ4), v UInt64 CODEC(LZ4), s String CODEC(LZ4), ver UInt32 CODEC(LZ4)) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

CREATE TABLE final_lab.s_1p (id UInt64 CODEC(LZ4), v UInt64 CODEC(LZ4), s String CODEC(LZ4), ver UInt32 CODEC(LZ4)) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

CREATE TABLE final_lab.s_10p (id UInt64 CODEC(LZ4), v UInt64 CODEC(LZ4), s String CODEC(LZ4), ver UInt32 CODEC(LZ4)) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

CREATE TABLE final_lab.s_part (id UInt64 CODEC(LZ4), v UInt64 CODEC(LZ4), s String CODEC(LZ4), ver UInt32 CODEC(LZ4)) ENGINE = ReplacingMergeTree(ver) PARTITION BY id % 16 ORDER BY id;

INSERT INTO final_lab.s_mt SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

INSERT INTO final_lab.s_clean SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

INSERT INTO final_lab.s_1p SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

INSERT INTO final_lab.s_10p SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

INSERT INTO final_lab.s_part SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

OPTIMIZE TABLE final_lab.s_mt FINAL;

OPTIMIZE TABLE final_lab.s_clean FINAL;

OPTIMIZE TABLE final_lab.s_1p FINAL;

OPTIMIZE TABLE final_lab.s_10p FINAL;

OPTIMIZE TABLE final_lab.s_part FINAL;

SYSTEM STOP MERGES final_lab.s_mt;

SYSTEM STOP MERGES final_lab.s_clean;

SYSTEM STOP MERGES final_lab.s_1p;

SYSTEM STOP MERGES final_lab.s_10p;

SYSTEM STOP MERGES final_lab.s_part;

INSERT INTO final_lab.s_1p SELECT number, number + 1, repeat('a', 20), 2 FROM numbers(20000000) WHERE number % 100 = 0;

INSERT INTO final_lab.s_10p SELECT number, number + 1, repeat('a', 20), 2 FROM numbers(20000000) WHERE number % 10 = 0;

INSERT INTO final_lab.s_part SELECT number, number + 1, repeat('a', 20), 2 FROM numbers(20000000) WHERE number % 100 = 0;

-- probe: 07-mt-plain repeat=5
-- Control. Correct: sum(v) 199999990000000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_mt;

-- probe: 07-clean-final repeat=5
-- Correct: sum(v) 199999990000000, count 20000000 (no duplicates, FINAL on one part).
SELECT sum(v), count() FROM final_lab.s_clean FINAL;

-- probe: 07-1p-plain repeat=5
-- Wrong answer on purpose, speed only. Correct with FINAL: sum(v) 199999990000000 + 200000 = 199999990200000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_1p;

-- probe: 07-1p-final repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_1p FINAL;

-- probe: 07-1p-final-novertical repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_1p FINAL SETTINGS enable_vertical_final = 0;

-- probe: 07-1p-final-1thread repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_1p FINAL SETTINGS max_final_threads = 1;

-- probe: 07-1p-argmax repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM (SELECT id, argMax(v, ver) AS v FROM final_lab.s_1p GROUP BY id);

-- probe: 07-1p-limitby repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM (SELECT id, v FROM final_lab.s_1p ORDER BY id, ver DESC LIMIT 1 BY id);

-- probe: 07-10p-final repeat=5
-- Correct: sum(v) 199999992000000 (+ 2000000), count 20000000.
SELECT sum(v), count() FROM final_lab.s_10p FINAL;

-- probe: 07-10p-argmax repeat=5
-- Correct: sum(v) 199999992000000, count 20000000.
SELECT sum(v), count() FROM (SELECT id, argMax(v, ver) AS v FROM final_lab.s_10p GROUP BY id);

-- probe: 07-1p-range-final repeat=5
-- Correct: count 100000, sum(v) 1004999951000 (sum(10000000..10099999) = 1004999950000, plus 1 for each of the 1000 re-written keys).
SELECT sum(v), count() FROM final_lab.s_1p FINAL WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 07-1p-range-plain repeat=5
-- Wrong answer on purpose (counts 101000 rows), speed only.
SELECT sum(v), count() FROM final_lab.s_1p WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 07-part-final repeat=5
-- Correct: sum(v) 199999990200000, count 20000000.
SELECT sum(v), count() FROM final_lab.s_part FINAL;

-- probe: 07-part-final-dnm1 repeat=5
-- Correct: sum(v) 199999990200000, count 20000000 (no key crosses partitions).
SELECT sum(v), count() FROM final_lab.s_part FINAL SETTINGS do_not_merge_across_partitions_select_final = 1;

-- probe: 07-part-final-auto0 repeat=5
-- Correct: sum(v) 199999990200000, count 20000000 (setting exists only on newer builds).
SELECT sum(v), count() FROM final_lab.s_part FINAL SETTINGS enable_automatic_decision_for_merging_across_partitions_for_final = 0;

-- probe: 07-1p-check value
-- Correct: 1 (FINAL and argMax agree).
SELECT (SELECT sum(v) FROM final_lab.s_1p FINAL) = (SELECT sum(v) FROM (SELECT id, argMax(v, ver) AS v FROM final_lab.s_1p GROUP BY id));

-- probe: 07-10p-check value
-- Correct: 1 (FINAL and argMax agree).
SELECT (SELECT sum(v) FROM final_lab.s_10p FINAL) = (SELECT sum(v) FROM (SELECT id, argMax(v, ver) AS v FROM final_lab.s_10p GROUP BY id));

-- probe: 07-codec show
-- The part default codec and the declared column codec of s_1p on this build (the column codec is what the data is written with).
SELECT
    (SELECT groupUniqArray(default_compression_codec) FROM system.parts WHERE database = 'final_lab' AND table = 's_1p' AND active) AS part_default,
    (SELECT groupUniqArray(compression_codec) FROM system.columns WHERE database = 'final_lab' AND table = 's_1p') AS column_codec;
