-- settings: enable_lightweight_update, apply_patch_parts, apply_patches_on_merge, remove_unused_patch_parts, max_uncompressed_bytes_in_patches
-- Patch parts pile up: successive one-row UPDATEs on one table, merges stopped. After 1, 10 and 50 updates:
-- the number of active patch parts and the cost of a full scan and of a point read. Then the patches are
-- applied by OPTIMIZE ... FINAL and then by ALTER TABLE ... APPLY PATCHES, with the same reads after each.
-- Table: 2M rows, one part, v = id, patches touch ids 1000..1049.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.pacc;

CREATE TABLE upsert_lab.pacc (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.pacc SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.pacc FINAL;

SYSTEM STOP MERGES upsert_lab.pacc;

-- probe: 06-parts-0 value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-0 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-0 repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;

-- probe: 06-update-01
UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1000 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 06-parts-1 value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-1 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-1 repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1001 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1002 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1003 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1004 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1005 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1006 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1007 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1008 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1009 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 06-parts-10 value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-10 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-10 repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1010 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1011 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1012 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1013 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1014 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1015 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1016 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1017 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1018 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1019 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1020 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1021 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1022 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1023 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1024 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1025 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1026 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1027 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1028 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1029 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1030 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1031 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1032 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1033 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1034 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1035 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1036 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1037 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1038 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1039 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1040 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1041 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1042 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1043 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1044 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1045 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1046 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1047 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1048 SETTINGS allow_experimental_lightweight_update = 1;

UPDATE upsert_lab.pacc SET v = v + 1 WHERE id = 1049 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 06-parts-50 value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-50 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-50 repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;

SYSTEM START MERGES upsert_lab.pacc;

-- probe: 06-optimize
-- OPTIMIZE ... FINAL on a one-part table: does it apply the patches?
OPTIMIZE TABLE upsert_lab.pacc FINAL;


-- probe: 06-parts-optimized value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-optimized repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-optimized repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;

-- probe: 06-apply-patches
-- The dedicated command (needs merges running, so it comes after SYSTEM START MERGES). Where the version has no such command this is a syntax error.
ALTER TABLE upsert_lab.pacc APPLY PATCHES SETTINGS mutations_sync = 2;

-- probe: 06-parts-applied value
-- active patch parts / their rows / name of the base part (its last number moves when it is rewritten)
SELECT countIf(startsWith(name, 'patch-')), sumIf(rows, startsWith(name, 'patch-')), anyIf(name, NOT startsWith(name, 'patch-')) FROM system.parts WHERE database = 'upsert_lab' AND table = 'pacc' AND active;

-- probe: 06-scan-applied repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pacc;

-- probe: 06-point-applied repeat=5 value
SELECT v FROM upsert_lab.pacc WHERE id = 1000;
