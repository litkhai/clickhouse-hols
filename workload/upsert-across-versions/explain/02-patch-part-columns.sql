-- 02: why the same patch part is about 2x the bytes from 26.8 on (files 04 and 08, item 2 of README 'Explained')
-- The pu_1p table of file 04 (2M rows, 1% UPDATE), twice:
--   pc_v_default  the build's default patch_parts_version (v1 behaviour before 26.8, v2 from 26.8)
--   pc_v1         patch_parts_version = 'v1'. The setting exists from 26.8; on 25.8 and 26.3 this CREATE fails
--                 with Code 115 (UNKNOWN_SETTING) and the statements on pc_v1 fail after it.
-- Run: clickhouse-client --multiquery --ignore-error < explain/02-patch-part-columns.sql

CREATE DATABASE IF NOT EXISTS upsert_explain;

DROP TABLE IF EXISTS upsert_explain.pc_v_default;
DROP TABLE IF EXISTS upsert_explain.pc_v1;

CREATE TABLE upsert_explain.pc_v_default (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;
INSERT INTO upsert_explain.pc_v_default SELECT number, number, repeat('x', 20) FROM numbers(2000000);
OPTIMIZE TABLE upsert_explain.pc_v_default FINAL;
SYSTEM STOP MERGES upsert_explain.pc_v_default;
UPDATE upsert_explain.pc_v_default SET v = v + 1 WHERE id % 100 = 0;

CREATE TABLE upsert_explain.pc_v1 (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1, patch_parts_version = 'v1';
INSERT INTO upsert_explain.pc_v1 SELECT number, number, repeat('x', 20) FROM numbers(2000000);
OPTIMIZE TABLE upsert_explain.pc_v1 FINAL;
SYSTEM STOP MERGES upsert_explain.pc_v1;
UPDATE upsert_explain.pc_v1 SET v = v + 1 WHERE id % 100 = 0;

-- the patch part: rows, compressed and uncompressed bytes
SELECT table, rows, data_compressed_bytes, data_uncompressed_bytes
FROM system.parts WHERE database = 'upsert_explain' AND table IN ('pc_v_default', 'pc_v1') AND active AND startsWith(name, 'patch-')
ORDER BY table;

-- its columns (a patch part is Compact, so system.parts_columns has no per-column sizes)
SELECT table, groupArray(column) AS columns
FROM system.parts_columns WHERE database = 'upsert_explain' AND table IN ('pc_v_default', 'pc_v1') AND active AND startsWith(name, 'patch-')
GROUP BY table ORDER BY table;
