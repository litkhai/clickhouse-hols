-- settings: apply_mutations_on_fly, mutations_sync, max_streams_for_merge_tree_reading
-- A classic mutation that has not run yet: SYSTEM STOP MERGES keeps it pending, the ALTER returns at once
-- (mutations_sync = 0), and a SELECT with apply_mutations_on_fly = 1 applies the pending change while reading.
-- Table: 2M rows, one part, v = id; the mutation adds 1 to v for every 100th row (+20000 to sum(v)).

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.otf;

CREATE TABLE upsert_lab.otf (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.otf SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.otf FINAL;

SYSTEM STOP MERGES upsert_lab.otf;

-- probe: 05-alter-async
-- Returns before anything is rewritten.
ALTER TABLE upsert_lab.otf UPDATE v = v + 1 WHERE id % 100 = 0 SETTINGS mutations_sync = 0;

-- probe: 05-pending value
-- mutations not done / parts still to do (expected 1 / 1)
SELECT countIf(NOT is_done), sum(parts_to_do) FROM system.mutations WHERE database = 'upsert_lab' AND table = 'otf';

-- probe: 05-read-on-fly value
-- Positive: the new value is visible (expected 1999999020000).
SELECT sum(v) AS s FROM upsert_lab.otf SETTINGS apply_mutations_on_fly = 1;

-- probe: 05-read-on-fly-repeat repeat=5
SELECT sum(v) AS s FROM upsert_lab.otf SETTINGS apply_mutations_on_fly = 1;

-- probe: 05-read-plain value
-- Negative: the old value (expected 1999999000000).
SELECT sum(v) AS s FROM upsert_lab.otf SETTINGS apply_mutations_on_fly = 0;

-- probe: 05-read-plain-repeat repeat=5
SELECT sum(v) AS s FROM upsert_lab.otf SETTINGS apply_mutations_on_fly = 0;

SYSTEM START MERGES upsert_lab.otf;
