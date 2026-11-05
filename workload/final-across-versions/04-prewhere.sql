-- PREWHERE and FINAL. Part 1: correctness on a small table. Part 2: the read cost of a filter on a sorting-key
-- column that the primary key cannot use (10M rows), with and without FINAL.
-- Merges are stopped on every table after the base insert.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.pw_small;

DROP TABLE IF EXISTS final_lab.pw;

DROP TABLE IF EXISTS final_lab.pw_mt;

CREATE TABLE final_lab.pw_small
(
    id  UInt64,
    v   UInt64,
    s   String,
    ver UInt32
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY id;

SYSTEM STOP MERGES final_lab.pw_small;

INSERT INTO final_lab.pw_small SELECT number, 1, repeat('x', 50), 1 FROM numbers(100000);

INSERT INTO final_lab.pw_small SELECT number, 2, repeat('x', 50), 2 FROM numbers(100000) WHERE number % 100 = 0;

-- probe: 04-small-where value
-- Correct: 99000 (1000 keys have newest v = 2; FINAL first, then the filter).
SELECT count() FROM final_lab.pw_small FINAL WHERE v = 1;

-- probe: 04-small-where-move1 value
-- Correct: 99000.
SELECT count() FROM final_lab.pw_small FINAL WHERE v = 1 SETTINGS optimize_move_to_prewhere_if_final = 1;

-- probe: 04-small-where-move0 value
-- Correct: 99000.
SELECT count() FROM final_lab.pw_small FINAL WHERE v = 1 SETTINGS optimize_move_to_prewhere_if_final = 0;

-- probe: 04-small-prewhere value
-- Correct: 99000 (FINAL semantics: the filter applies to the newest row of each key).
SELECT count() FROM final_lab.pw_small FINAL PREWHERE v = 1;

-- probe: 04-small-prewhere-after value
-- Correct: 99000 (setting exists only on newer builds).
SELECT count() FROM final_lab.pw_small FINAL PREWHERE v = 1 SETTINGS apply_prewhere_after_final = 1;

-- All columns of pw and pw_mt carry CODEC(LZ4): from 26.9 a part of 100 MB or more defaults to ZSTD(3), older builds use LZ4,
-- and these parts are about 275 MiB, so without the pin the read-cost probes would compare codecs as well as builds.
CREATE TABLE final_lab.pw
(
    ts  DateTime('UTC') CODEC(LZ4),
    id  UInt64 CODEC(LZ4),
    s   String CODEC(LZ4),
    ver UInt32 CODEC(LZ4)
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY (ts, id);

CREATE TABLE final_lab.pw_mt
(
    ts  DateTime('UTC') CODEC(LZ4),
    id  UInt64 CODEC(LZ4),
    s   String CODEC(LZ4),
    ver UInt32 CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY (ts, id);

INSERT INTO final_lab.pw SELECT toDateTime('2026-01-01 00:00:00', 'UTC') + number, number, repeat(hex(sipHash64(number)), 6), 1 FROM numbers(10000000);

INSERT INTO final_lab.pw_mt SELECT toDateTime('2026-01-01 00:00:00', 'UTC') + number, number, repeat(hex(sipHash64(number)), 6), 1 FROM numbers(10000000);

OPTIMIZE TABLE final_lab.pw FINAL;

OPTIMIZE TABLE final_lab.pw_mt FINAL;

SYSTEM STOP MERGES final_lab.pw;

INSERT INTO final_lab.pw SELECT toDateTime('2026-01-01 00:00:00', 'UTC') + number, number, repeat(hex(sipHash64(number)), 6), 2 FROM numbers(10000000) WHERE number % 100 = 0;

-- probe: 04-pw-final-default repeat=5
-- Correct (all four queries select the same rows): 417600 rows, sum(length(s)) 40070760
-- (10M seconds from a midnight start = 115 full days of 3600 matching seconds plus the first 3600 of the partial day; computed with `numbers(10000000) WHERE number % 86400 < 3600`).
SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600;

SYSTEM FLUSH LOGS;

-- probe: 04-pw-final-default-bytes value
SELECT min(read_bytes) FROM system.query_log WHERE type = 'QueryFinish' AND query_id LIKE '04-pw-final-default.%';

-- probe: 04-pw-final-move1 repeat=5
-- Correct: 417600 rows, 40070760 (same as above).
SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600 SETTINGS optimize_move_to_prewhere_if_final = 1;

SYSTEM FLUSH LOGS;

-- probe: 04-pw-final-move1-bytes value
SELECT min(read_bytes) FROM system.query_log WHERE type = 'QueryFinish' AND query_id LIKE '04-pw-final-move1.%';

-- probe: 04-pw-final-move0 repeat=5
-- Correct: 417600 rows, 40070760 (same as above).
SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600 SETTINGS optimize_move_to_prewhere_if_final = 0;

SYSTEM FLUSH LOGS;

-- probe: 04-pw-final-move0-bytes value
SELECT min(read_bytes) FROM system.query_log WHERE type = 'QueryFinish' AND query_id LIKE '04-pw-final-move0.%';

-- probe: 04-pw-mt repeat=5
-- Control, MergeTree without FINAL and without duplicates. Correct: 417600 rows, 40070760.
SELECT count(), sum(length(s)) FROM final_lab.pw_mt WHERE toUInt32(ts) % 86400 < 3600;

SYSTEM FLUSH LOGS;

-- probe: 04-pw-mt-bytes value
SELECT min(read_bytes) FROM system.query_log WHERE type = 'QueryFinish' AND query_id LIKE '04-pw-mt.%';

-- probe: 04-plan-prewhere-default value
-- Number of plan lines mentioning PREWHERE for the FINAL query with default settings (0 = the filter stayed a WHERE).
SELECT countIf(explain ILIKE '%prewhere%') FROM (EXPLAIN PLAN actions = 1 SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600);

-- probe: 04-plan-prewhere-move0 value
-- Same with optimize_move_to_prewhere_if_final = 0.
SELECT countIf(explain ILIKE '%prewhere%') FROM (EXPLAIN PLAN actions = 1 SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600 SETTINGS optimize_move_to_prewhere_if_final = 0);

-- probe: 04-plan-prewhere-move1 value
-- Same with optimize_move_to_prewhere_if_final = 1.
SELECT countIf(explain ILIKE '%prewhere%') FROM (EXPLAIN PLAN actions = 1 SELECT count(), sum(length(s)) FROM final_lab.pw FINAL WHERE toUInt32(ts) % 86400 < 3600 SETTINGS optimize_move_to_prewhere_if_final = 1);
