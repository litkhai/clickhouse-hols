-- CollapsingMergeTree and VersionedCollapsingMergeTree with the cancel row (sign = -1) inserted
-- BEFORE the state row (sign = 1), in separate INSERTs. 100000 keys carry a state row; every 100th
-- key (1000 keys) also has a cancel row. A correct collapse leaves 99000 keys.
-- Merges are stopped until the OPTIMIZE so that the "before" probes are deterministic.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.cmt_late;

DROP TABLE IF EXISTS upsert_lab.cmt_ok;

DROP TABLE IF EXISTS upsert_lab.vcmt_late;

CREATE TABLE upsert_lab.cmt_late (id UInt64, v UInt64, sign Int8) ENGINE = CollapsingMergeTree(sign) ORDER BY id;

CREATE TABLE upsert_lab.cmt_ok (id UInt64, v UInt64, sign Int8) ENGINE = CollapsingMergeTree(sign) ORDER BY id;

CREATE TABLE upsert_lab.vcmt_late (id UInt64, v UInt64, sign Int8, ver UInt32) ENGINE = VersionedCollapsingMergeTree(sign, ver) ORDER BY id;

SYSTEM STOP MERGES upsert_lab.cmt_late;

SYSTEM STOP MERGES upsert_lab.cmt_ok;

SYSTEM STOP MERGES upsert_lab.vcmt_late;

-- Cancel first, state second (the case under test).
INSERT INTO upsert_lab.cmt_late SELECT number * 100, 7, -1 FROM numbers(1000);

INSERT INTO upsert_lab.cmt_late SELECT number, 7, 1 FROM numbers(100000);

-- Control: state first, cancel second.
INSERT INTO upsert_lab.cmt_ok SELECT number, 7, 1 FROM numbers(100000);

INSERT INTO upsert_lab.cmt_ok SELECT number * 100, 7, -1 FROM numbers(1000);

INSERT INTO upsert_lab.vcmt_late SELECT number * 100, 7, -1, 1 FROM numbers(1000);

INSERT INTO upsert_lab.vcmt_late SELECT number, 7, 1, 1 FROM numbers(100000);

-- probe: 02-cmt-late-before value
-- rows physically stored / net sign / keys with sum(sign) > 0
SELECT count(), sum(sign), uniqIf(id, sign = 1) FROM upsert_lab.cmt_late;

-- probe: 02-cmt-late-final value
-- FINAL: rows / net sign
SELECT count(), sum(sign) FROM upsert_lab.cmt_late FINAL;

-- probe: 02-cmt-late-sumsign value
-- The documented way to read without relying on a merge: HAVING sum(sign) > 0 (expected 99000 keys).
SELECT count() FROM (SELECT id FROM upsert_lab.cmt_late GROUP BY id HAVING sum(sign) > 0);

SYSTEM START MERGES upsert_lab.cmt_late;

SYSTEM START MERGES upsert_lab.cmt_ok;

SYSTEM START MERGES upsert_lab.vcmt_late;

-- probe: 02-cmt-late-optimize
OPTIMIZE TABLE upsert_lab.cmt_late FINAL;

-- probe: 02-cmt-ok-optimize
OPTIMIZE TABLE upsert_lab.cmt_ok FINAL;

-- probe: 02-vcmt-late-optimize
OPTIMIZE TABLE upsert_lab.vcmt_late FINAL;

-- probe: 02-cmt-late-after value
-- cancel first: rows left / sum(sign) / cancel rows left
SELECT count(), sum(sign), countIf(sign = -1) FROM upsert_lab.cmt_late;

-- probe: 02-cmt-ok-after value
-- state first (control): rows left / sum(sign) / cancel rows left (expected 99000 / 99000 / 0)
SELECT count(), sum(sign), countIf(sign = -1) FROM upsert_lab.cmt_ok;

-- probe: 02-vcmt-late-after value
-- cancel first with VersionedCollapsingMergeTree: rows left / sum(sign) / cancel rows left
SELECT count(), sum(sign), countIf(sign = -1) FROM upsert_lab.vcmt_late;
