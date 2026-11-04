-- settings: lightweight_delete_mode, lightweight_deletes_sync, enable_lightweight_delete, apply_deleted_mask, enable_block_number_column, enable_block_offset_column
-- Three ways to delete 1% (id % 100 = 0) of 2M rows, one table each, one part before the delete:
--   del_alter  ALTER TABLE ... DELETE WHERE ...                 (classic mutation, rewrites the part)
--   del_light  DELETE FROM ... WHERE ...                        (lightweight; the mode is the server default)
--   del_patch  DELETE FROM ... SETTINGS lightweight_delete_mode = 'lightweight_update'
--              (a patch part marks the rows; where the version has the mode, the table needs the block columns)
-- Bytes written = ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] of the part_log rows.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.del_alter;

DROP TABLE IF EXISTS upsert_lab.del_light;

DROP TABLE IF EXISTS upsert_lab.del_patch;

CREATE TABLE upsert_lab.del_alter (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.del_alter SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.del_alter FINAL;

CREATE TABLE upsert_lab.del_light (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.del_light SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.del_light FINAL;

-- probe: 07-alter-delete
ALTER TABLE upsert_lab.del_alter DELETE WHERE id % 100 = 0 SETTINGS mutations_sync = 2;

-- probe: 07-delete-from
DELETE FROM upsert_lab.del_light WHERE id % 100 = 0;

SYSTEM FLUSH LOGS;

-- probe: 07-alter-delete-bytes value
-- bytes written / new part rows / events
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS part_rows, count() AS events
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'del_alter' AND event_type = 'MutatePart';

-- probe: 07-delete-from-bytes value
-- bytes written / new part rows / events: on 26.10 the default mode is alter_update (a mutation of the hidden _row_exists column)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS part_rows, count() AS events
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'del_light' AND event_type = 'MutatePart';

-- probe: 07-alter-count value
-- Expected 1980000.
SELECT count() FROM upsert_lab.del_alter;

-- probe: 07-alter-count-nomask value
-- Control: the rows are physically gone, the mask does not matter (expected 1980000).
SELECT count() FROM upsert_lab.del_alter SETTINGS apply_deleted_mask = 0;

-- probe: 07-delete-count value
-- Expected 1980000.
SELECT count() FROM upsert_lab.del_light;

-- probe: 07-delete-count-nomask value
-- Negative: with the mask off the deleted rows are back (expected 2000000).
SELECT count() FROM upsert_lab.del_light SETTINGS apply_deleted_mask = 0;

-- probe: 07-delete-parts value
-- rows in the active parts of del_light: the rows are still stored (expected 2000000)
SELECT sum(rows) FROM system.parts WHERE database = 'upsert_lab' AND table = 'del_light' AND active;

-- probe: 07-scan-alter repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.del_alter;

-- probe: 07-scan-delete repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.del_light;

CREATE TABLE upsert_lab.del_patch (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.del_patch SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.del_patch FINAL;

SYSTEM STOP MERGES upsert_lab.del_patch;

-- probe: 07-delete-patch
DELETE FROM upsert_lab.del_patch WHERE id % 100 = 0 SETTINGS lightweight_delete_mode = 'lightweight_update';

SYSTEM FLUSH LOGS;

-- probe: 07-delete-patch-bytes value
-- bytes written by patch parts / bytes written by MutatePart (nonzero = the server fell back to a mutation)
SELECT sumIf(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'], event_type = 'NewPart' AND startsWith(part_name, 'patch-')) AS patch_written_bytes,
       sumIf(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'], event_type = 'MutatePart') AS mutate_written_bytes
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'del_patch';

-- probe: 07-delete-patch-parts value
-- active patch parts / their rows
SELECT count(), sum(rows) FROM system.parts WHERE database = 'upsert_lab' AND table = 'del_patch' AND active AND startsWith(name, 'patch-');

-- probe: 07-delete-patch-count value
-- Expected 1980000.
SELECT count() FROM upsert_lab.del_patch;

-- probe: 07-delete-patch-count-nomask value
-- Negative: with the mask off (expected 2000000).
SELECT count() FROM upsert_lab.del_patch SETTINGS apply_deleted_mask = 0;

-- probe: 07-scan-patch repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.del_patch;

SYSTEM START MERGES upsert_lab.del_patch;
