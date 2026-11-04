-- Probes whose error is the result: each fails even on 26.10, so tools/hol (top-level files only) skips this directory.
-- The runner records the error code per version.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.err_plain;

DROP TABLE IF EXISTS upsert_lab.err_patch;

DROP TABLE IF EXISTS upsert_lab.err_rmt;

CREATE TABLE upsert_lab.err_plain (id UInt64, v UInt64) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.err_plain SELECT number, number FROM numbers(1000);

CREATE TABLE upsert_lab.err_rmt (id UInt64, v UInt64, ver UInt32, is_deleted UInt8) ENGINE = ReplacingMergeTree(ver, is_deleted) ORDER BY id;

INSERT INTO upsert_lab.err_rmt SELECT number, number, 1, number % 2 FROM numbers(1000);

-- probe: err-update-no-block-columns
-- UPDATE on a table without enable_block_number_column / enable_block_offset_column.
UPDATE upsert_lab.err_plain SET v = v + 1 WHERE id = 1 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: err-delete-force-no-block-columns
-- lightweight_update_force on the same table: no fallback to a mutation.
DELETE FROM upsert_lab.err_plain WHERE id = 1 SETTINGS lightweight_delete_mode = 'lightweight_update_force';

-- probe: err-cleanup-without-table-setting
-- FINAL CLEANUP on a table that was not created with allow_experimental_replacing_merge_with_cleanup = 1.
OPTIMIZE TABLE upsert_lab.err_rmt FINAL CLEANUP;

CREATE TABLE upsert_lab.err_patch (id UInt64, v UInt64) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.err_patch SELECT number, number FROM numbers(1000);

-- probe: err-update-sorting-key
-- A patch-part UPDATE cannot change a sorting-key column.
UPDATE upsert_lab.err_patch SET id = id + 1 WHERE id = 5 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: err-alter-update-sorting-key
-- Nor can a classic mutation.
ALTER TABLE upsert_lab.err_patch UPDATE id = id + 1 WHERE id = 5 SETTINGS mutations_sync = 2;
