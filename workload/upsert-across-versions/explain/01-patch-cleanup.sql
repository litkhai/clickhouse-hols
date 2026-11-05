-- 01: when is a patch part that APPLY PATCHES has made unused removed? (file 06, item 1 of README 'Explained')
-- Three copies of the 06 table, 10 one-row UPDATEs each instead of 50, then OPTIMIZE ... FINAL and APPLY PATCHES:
--   pc_default  default cleanup settings
--   pc_fast     the cleanup runs every second (cleanup_delay_period = max_cleanup_delay_period = 1)
--   pc_off      the same cadence as pc_fast, remove_unused_patch_parts = 0
-- The last SELECT runs 3 s after APPLY PATCHES. Run: clickhouse-client --multiquery < explain/01-patch-cleanup.sql
-- 25.8 or later (patch-part UPDATE).

CREATE DATABASE IF NOT EXISTS upsert_explain;

DROP TABLE IF EXISTS upsert_explain.pc_default;
DROP TABLE IF EXISTS upsert_explain.pc_fast;
DROP TABLE IF EXISTS upsert_explain.pc_off;
CREATE TABLE upsert_explain.pc_default (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;
CREATE TABLE upsert_explain.pc_fast (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1, cleanup_delay_period = 1, max_cleanup_delay_period = 1, cleanup_delay_period_random_add = 0;
CREATE TABLE upsert_explain.pc_off (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1, cleanup_delay_period = 1, max_cleanup_delay_period = 1, cleanup_delay_period_random_add = 0, remove_unused_patch_parts = 0;

INSERT INTO upsert_explain.pc_default SELECT number, number, repeat('x', 20) FROM numbers(2000000);
OPTIMIZE TABLE upsert_explain.pc_default FINAL;
SYSTEM STOP MERGES upsert_explain.pc_default;
INSERT INTO upsert_explain.pc_fast SELECT number, number, repeat('x', 20) FROM numbers(2000000);
OPTIMIZE TABLE upsert_explain.pc_fast FINAL;
SYSTEM STOP MERGES upsert_explain.pc_fast;
INSERT INTO upsert_explain.pc_off SELECT number, number, repeat('x', 20) FROM numbers(2000000);
OPTIMIZE TABLE upsert_explain.pc_off FINAL;
SYSTEM STOP MERGES upsert_explain.pc_off;

UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1000;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1001;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1002;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1003;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1004;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1005;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1006;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1007;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1008;
UPDATE upsert_explain.pc_default SET v = v + 1 WHERE id = 1009;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1000;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1001;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1002;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1003;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1004;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1005;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1006;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1007;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1008;
UPDATE upsert_explain.pc_fast SET v = v + 1 WHERE id = 1009;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1000;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1001;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1002;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1003;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1004;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1005;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1006;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1007;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1008;
UPDATE upsert_explain.pc_off SET v = v + 1 WHERE id = 1009;

SYSTEM START MERGES upsert_explain.pc_default;
OPTIMIZE TABLE upsert_explain.pc_default FINAL;
ALTER TABLE upsert_explain.pc_default APPLY PATCHES SETTINGS mutations_sync = 2;
SYSTEM START MERGES upsert_explain.pc_fast;
OPTIMIZE TABLE upsert_explain.pc_fast FINAL;
ALTER TABLE upsert_explain.pc_fast APPLY PATCHES SETTINGS mutations_sync = 2;
SYSTEM START MERGES upsert_explain.pc_off;
OPTIMIZE TABLE upsert_explain.pc_off FINAL;
ALTER TABLE upsert_explain.pc_off APPLY PATCHES SETTINGS mutations_sync = 2;

SELECT 'waited 3 s' AS step WHERE sleep(3) = 0;

-- active patch parts per table, 3 s after APPLY PATCHES; and the data version of the base part
SELECT table, countIf(startsWith(name, 'patch-')) AS patch_parts, maxIf(data_version, NOT startsWith(name, 'patch-')) AS base_data_version
FROM system.parts WHERE database = 'upsert_explain' AND table IN ('pc_default', 'pc_fast', 'pc_off') AND active
GROUP BY table ORDER BY table;
