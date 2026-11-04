-- ClickHouse 25.7 Feature: SQL UPDATE (patch parts) and DELETE
-- Purpose: run the new `UPDATE t SET ... WHERE ...` and look at what it writes:
--          a small patch part next to the untouched data part. Compare with
--          `ALTER TABLE t UPDATE ...` on an identical table, which rewrites parts.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-07
-- Needs (confirmed on 25.7.8.71, see 01-sql-update-delete.sh for the errors without them):
--   session setting allow_experimental_lightweight_update = 1
--   table settings   enable_block_number_column = 1, enable_block_offset_column = 1
-- The statements that are refused raise exceptions, so they run in the .sh, not here.

SET allow_experimental_lightweight_update = 1;

DROP TABLE IF EXISTS inv_patch;
DROP TABLE IF EXISTS inv_alter;
DROP TABLE IF EXISTS inv_marker;

-- The part_log query in section 5 reads only what happened after this instant.
CREATE TABLE inv_marker (t DateTime64(6)) ENGINE = Memory;
INSERT INTO inv_marker SELECT now64(6);

-- 1. The settings, as the server reports them
SELECT '=== 1. Settings as the server reports them (enable_block_* default to 0) ===' AS title;
SELECT name, value, description FROM system.settings
WHERE name IN ('allow_experimental_lightweight_update', 'apply_patch_parts') ORDER BY name;
SELECT name, value FROM system.merge_tree_settings
WHERE name IN ('enable_block_number_column', 'enable_block_offset_column', 'apply_patches_on_merge', 'remove_unused_patch_parts')
ORDER BY name;

-- 2. Two identical tables, 1,000,000 rows each, one part per table.
SELECT '=== 2. Two identical tables, 1,000,000 rows ===' AS title;

CREATE TABLE inv_patch
(
    product_id UInt64,
    category   LowCardinality(String),
    quantity   UInt32,
    note       String
)
ENGINE = MergeTree
ORDER BY product_id
SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

CREATE TABLE inv_alter AS inv_patch ENGINE = MergeTree ORDER BY product_id
SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO inv_patch SELECT number, ['Electronics', 'Clothing', 'Books', 'Home'][1 + number % 4], 100 + number % 900, randomPrintableASCII(30)
FROM numbers(1000000) SETTINGS max_block_size = 1000000, max_insert_threads = 1, min_insert_block_size_rows = 1000000;
INSERT INTO inv_alter SELECT * FROM inv_patch;

SELECT count() AS rows_patch, countIf(quantity = 0) AS zero_qty FROM inv_patch;

-- 3. UPDATE ... SET ... WHERE: a patch part
SELECT '=== 3. UPDATE inv_patch SET ... (patch part) ===' AS title;

UPDATE inv_patch SET quantity = 0 WHERE category = 'Books';

SELECT '--- parts: the data part is untouched, a patch-... part holds the changed rows' AS step;
SELECT name, rows, bytes_on_disk, active FROM system.parts
WHERE database = currentDatabase() AND table = 'inv_patch' ORDER BY name;

SELECT '--- the new value is visible at once (the patch is applied on SELECT)' AS step;
SELECT category, count() AS products, countIf(quantity = 0) AS zero_qty FROM inv_patch GROUP BY category ORDER BY category;

SELECT '--- no mutation was created' AS step;
SELECT count() AS mutations FROM system.mutations WHERE database = currentDatabase() AND table = 'inv_patch';

-- 4. ALTER TABLE ... UPDATE on the identical table: a mutation that rewrites parts
SELECT '=== 4. ALTER TABLE inv_alter UPDATE ... (mutation, rewritten part) ===' AS title;

ALTER TABLE inv_alter UPDATE quantity = 0 WHERE category = 'Books' SETTINGS mutations_sync = 2;

SELECT '--- parts: the old part is inactive, a new part with the mutation version _N replaced it' AS step;
SELECT name, rows, bytes_on_disk, active FROM system.parts
WHERE database = currentDatabase() AND table = 'inv_alter' ORDER BY name;

SELECT '--- the mutation' AS step;
SELECT command, is_done FROM system.mutations WHERE database = currentDatabase() AND table = 'inv_alter';

SELECT '--- same result' AS step;
SELECT category, count() AS products, countIf(quantity = 0) AS zero_qty FROM inv_alter GROUP BY category ORDER BY category;

-- 5. What each wrote, from system.part_log
SELECT '=== 5. What each wrote (system.part_log) ===' AS title;
SYSTEM FLUSH LOGS;
SELECT table, event_type, part_name, rows, size_in_bytes AS part_bytes, bytes_uncompressed, duration_ms
FROM system.part_log
WHERE database = currentDatabase() AND table IN ('inv_patch', 'inv_alter')
  AND ((event_type = 'NewPart' AND part_name LIKE 'patch-%') OR event_type = 'MutatePart')
  AND event_time_microseconds >= (SELECT max(t) FROM inv_marker)
ORDER BY event_time_microseconds;
-- part_bytes of a mutated part is the size of the whole new part; the patch part is only the changed rows.

-- 6. A merge folds the patch into the data part
SELECT '=== 6. OPTIMIZE ... FINAL merges the patch in (apply_patches_on_merge) ===' AS title;
OPTIMIZE TABLE inv_patch FINAL;
SELECT name, rows, bytes_on_disk, active FROM system.parts
WHERE database = currentDatabase() AND table = 'inv_patch' AND active ORDER BY name;
SELECT '--- with patches switched off on read, the merged part already holds the new values' AS step;
SELECT countIf(quantity = 0) AS zero_qty_without_patches FROM inv_patch SETTINGS apply_patch_parts = 0;
-- The patch part itself stays listed until the background cleanup (remove_unused_patch_parts) drops it.

-- 7. DELETE FROM: lightweight delete
SELECT '=== 7. DELETE FROM (lightweight delete) ===' AS title;
DELETE FROM inv_patch WHERE category = 'Clothing';

SELECT count() AS rows_left, countIf(category = 'Clothing') AS clothing_left FROM inv_patch;

SELECT '--- what it is: a mutation that sets the hidden _row_exists = 0, not a patch part' AS step;
SELECT command, is_done FROM system.mutations WHERE database = currentDatabase() AND table = 'inv_patch';

SELECT '--- the rows are still on disk until a merge' AS step;
SELECT name, rows, active FROM system.parts
WHERE database = currentDatabase() AND table = 'inv_patch' AND active ORDER BY name;
SELECT sum(rows) AS rows_in_active_data_parts FROM system.parts
WHERE database = currentDatabase() AND table = 'inv_patch' AND active AND name NOT LIKE 'patch-%';

-- Cleanup (commented out for inspection)
-- DROP TABLE inv_patch; DROP TABLE inv_alter; DROP TABLE inv_marker;

SELECT '✅ SQL UPDATE/DELETE test complete' AS status;
