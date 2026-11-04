-- settings: allow_experimental_replacing_merge_with_cleanup, clean_deleted_rows
-- ReplacingMergeTree: the newest row per key wins, but only when parts merge or FINAL is asked for.
-- Base insert of 2M keys (ver = 1), then a second insert that re-writes 1% of the keys with ver = 2
-- and marks 0.1% of all keys (every tenth re-written key) is_deleted = 1.
-- Merges are stopped on both tables so that "before the merge" is deterministic.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.rmt;

DROP TABLE IF EXISTS upsert_lab.rmt_del;

CREATE TABLE upsert_lab.rmt
(
    id  UInt64,
    v   UInt64,
    ver UInt32
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY id;

SYSTEM STOP MERGES upsert_lab.rmt;

INSERT INTO upsert_lab.rmt SELECT number, number, 1 FROM numbers(2000000);

INSERT INTO upsert_lab.rmt SELECT number * 100, number * 100 + 1, 2 FROM numbers(20000);

-- The table setting is what OPTIMIZE ... FINAL CLEANUP asks for on 26.10; it is set at CREATE so one file runs everywhere.
-- Where a version does not know the setting (Code 115) the rest of this file is skipped and that is the result.
CREATE TABLE upsert_lab.rmt_del
(
    id         UInt64,
    v          UInt64,
    ver        UInt32,
    is_deleted UInt8
)
ENGINE = ReplacingMergeTree(ver, is_deleted)
ORDER BY id
SETTINGS allow_experimental_replacing_merge_with_cleanup = 1;

SYSTEM STOP MERGES upsert_lab.rmt_del;

INSERT INTO upsert_lab.rmt_del SELECT number, number, 1, 0 FROM numbers(2000000);

INSERT INTO upsert_lab.rmt_del SELECT number * 100, number * 100 + 1, 2, number % 10 = 0 FROM numbers(20000);

-- probe: 01-rmt-count-plain value
-- Negative: without FINAL the 20000 re-written keys are counted twice (expected 2020000).
SELECT count() FROM upsert_lab.rmt;

-- probe: 01-rmt-count-final value
-- Positive: FINAL collapses to one row per key (expected 2000000).
SELECT count() FROM upsert_lab.rmt FINAL;

-- probe: 01-rmt-final-agg repeat=5 value
SELECT sum(v) FROM upsert_lab.rmt FINAL;

-- probe: 01-rmt-argmax-agg repeat=5 value
-- The same answer without FINAL.
SELECT sum(v) FROM (SELECT id, argMax(v, ver) AS v FROM upsert_lab.rmt GROUP BY id);

-- probe: 01-rmt-del-count-plain value
-- Negative: 2020000 rows are physically there.
SELECT count() FROM upsert_lab.rmt_del;

-- probe: 01-rmt-del-count-final value
-- Positive: FINAL drops the 2000 deleted keys (expected 1998000).
SELECT count() FROM upsert_lab.rmt_del FINAL;

-- probe: 01-rmt-del-final-agg repeat=5 value
SELECT sum(v) FROM upsert_lab.rmt_del FINAL;

-- probe: 01-rmt-del-argmax-agg repeat=5 value
SELECT sum(v) FROM
(
    SELECT id, argMax(v, ver) AS v, argMax(is_deleted, ver) AS d
    FROM upsert_lab.rmt_del
    GROUP BY id
    HAVING d = 0
);

SYSTEM START MERGES upsert_lab.rmt;

SYSTEM START MERGES upsert_lab.rmt_del;

-- probe: 01-rmt-optimize
OPTIMIZE TABLE upsert_lab.rmt FINAL;

-- probe: 01-rmt-count-after-optimize value
-- Physical rows after the merge (expected 2000000).
SELECT count() FROM upsert_lab.rmt;

-- probe: 01-rmt-del-optimize
OPTIMIZE TABLE upsert_lab.rmt_del FINAL;

-- probe: 01-rmt-del-count-after-optimize value
-- A plain OPTIMIZE FINAL merges the versions but keeps the is_deleted = 1 rows (expected 2000000).
SELECT count() FROM upsert_lab.rmt_del;

-- probe: 01-rmt-del-cleanup
-- FINAL CLEANUP is what removes them.
OPTIMIZE TABLE upsert_lab.rmt_del FINAL CLEANUP;

-- probe: 01-rmt-del-count-after-cleanup value
-- Expected 1998000.
SELECT count() FROM upsert_lab.rmt_del;
