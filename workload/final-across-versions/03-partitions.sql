-- FINAL and partitions. In p_in_pk the partition key is a function of the sorting key, so no key crosses partitions.
-- In p_cross the same key lives in two partitions (January and February); the newer row is in February.
-- Merges are stopped on both tables.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.p_in_pk;

DROP TABLE IF EXISTS final_lab.p_cross;

CREATE TABLE final_lab.p_in_pk
(
    id  UInt64,
    v   UInt64,
    ver UInt32
)
ENGINE = ReplacingMergeTree(ver)
PARTITION BY id % 8
ORDER BY id;

SYSTEM STOP MERGES final_lab.p_in_pk;

INSERT INTO final_lab.p_in_pk SELECT number, number, 1 FROM numbers(2000000);

INSERT INTO final_lab.p_in_pk SELECT number, number + 1, 2 FROM numbers(2000000) WHERE number % 100 = 0;

-- probe: 03-inpk-final value
-- Correct: 2000000.
SELECT count() FROM final_lab.p_in_pk FINAL;

-- probe: 03-inpk-final-dnm value
-- Correct: 2000000 (no key crosses partitions).
SELECT count() FROM final_lab.p_in_pk FINAL SETTINGS do_not_merge_across_partitions_select_final = 1;

CREATE TABLE final_lab.p_cross
(
    id  UInt64,
    d   Date,
    v   UInt64,
    ver UInt32
)
ENGINE = ReplacingMergeTree(ver)
PARTITION BY toYYYYMM(d)
ORDER BY id;

SYSTEM STOP MERGES final_lab.p_cross;

INSERT INTO final_lab.p_cross SELECT number, '2026-01-15', number, 1 FROM numbers(1000000);

INSERT INTO final_lab.p_cross SELECT number, '2026-02-15', number + 1, 2 FROM numbers(1000000) WHERE number % 100 = 0;

-- probe: 03-cross-final value
-- Correct: 1000000.
SELECT count() FROM final_lab.p_cross FINAL;

-- probe: 03-cross-final-dnm value
-- Correct: 1000000 (the setting promises no key crosses partitions, but here 10000 keys do: record what it returns).
SELECT count() FROM final_lab.p_cross FINAL SETTINGS do_not_merge_across_partitions_select_final = 1;

-- probe: 03-cross-jan value
-- Correct: 990000 (the 10000 re-written keys have their newest row in February).
SELECT count() FROM final_lab.p_cross FINAL WHERE d < '2026-02-01';

-- probe: 03-cross-jan-nodefer value
-- Correct: 990000 (setting exists only on newer builds).
SELECT count() FROM final_lab.p_cross FINAL WHERE d < '2026-02-01' SETTINGS defer_partition_pruning_after_final = 0;

-- probe: 03-cross-feb value
-- Correct: 10000.
SELECT count() FROM final_lab.p_cross FINAL WHERE d >= '2026-02-01';

-- probe: 03-cross-jan-key500 value
-- Correct: 0 (key 500 was re-written, its newest row is in February).
SELECT count() FROM final_lab.p_cross FINAL WHERE d < '2026-02-01' AND id = 500;
