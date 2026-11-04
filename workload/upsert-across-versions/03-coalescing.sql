-- CoalescingMergeTree (new in 25.6): sparse inserts, each sets one column of a key, the others are NULL.
-- Same inserts into a ReplacingMergeTree for contrast. 1000 keys, three inserts: a, then b, then c.
-- Expect the first CREATE to fail before 25.6 (Code 73 UNKNOWN_STORAGE or similar): that is the result.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.coal;

DROP TABLE IF EXISTS upsert_lab.coal_rmt;

CREATE TABLE upsert_lab.coal_rmt (id UInt64, a Nullable(UInt64), b Nullable(UInt64), c Nullable(UInt64), ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

SYSTEM STOP MERGES upsert_lab.coal_rmt;

INSERT INTO upsert_lab.coal_rmt SELECT number, number, NULL, NULL, 1 FROM numbers(1000);

INSERT INTO upsert_lab.coal_rmt SELECT number, NULL, number * 2, NULL, 2 FROM numbers(1000);

INSERT INTO upsert_lab.coal_rmt SELECT number, NULL, NULL, number * 3, 3 FROM numbers(1000);

-- probe: 03-rmt-final value
-- ReplacingMergeTree FINAL keeps one whole row: rows / non-NULL a / non-NULL b / non-NULL c (expected 1000 / 0 / 0 / 1000)
SELECT count(), count(a), count(b), count(c) FROM upsert_lab.coal_rmt FINAL;

SYSTEM START MERGES upsert_lab.coal_rmt;

-- probe: 03-rmt-optimize
OPTIMIZE TABLE upsert_lab.coal_rmt FINAL;

-- probe: 03-rmt-after value
SELECT count(), count(a), count(b), count(c) FROM upsert_lab.coal_rmt;

CREATE TABLE upsert_lab.coal (id UInt64, a Nullable(UInt64), b Nullable(UInt64), c Nullable(UInt64)) ENGINE = CoalescingMergeTree ORDER BY id;

SYSTEM STOP MERGES upsert_lab.coal;

INSERT INTO upsert_lab.coal SELECT number, number, NULL, NULL FROM numbers(1000);

INSERT INTO upsert_lab.coal SELECT number, NULL, number * 2, NULL FROM numbers(1000);

INSERT INTO upsert_lab.coal SELECT number, NULL, NULL, number * 3 FROM numbers(1000);

-- probe: 03-coal-before value
-- Negative: before any merge the three sparse rows per key are all there (expected 3000 rows).
SELECT count(), count(a), count(b), count(c) FROM upsert_lab.coal;

-- probe: 03-coal-final value
-- FINAL: rows / non-NULL a / b / c (expected 1000 each)
SELECT count(), count(a), count(b), count(c) FROM upsert_lab.coal FINAL;

SYSTEM START MERGES upsert_lab.coal;

-- probe: 03-coal-optimize
OPTIMIZE TABLE upsert_lab.coal FINAL;

-- probe: 03-coal-after value
SELECT count(), count(a), count(b), count(c) FROM upsert_lab.coal;
