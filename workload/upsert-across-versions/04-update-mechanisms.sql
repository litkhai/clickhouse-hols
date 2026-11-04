-- settings: mutations_sync, enable_lightweight_update, allow_experimental_lightweight_update, apply_patch_parts, enable_block_number_column, enable_block_offset_column, apply_patches_on_merge, max_uncompressed_bytes_in_patches
-- The core measurement: three ways to change rows, each at 1 row, 1% and 10% of 2M rows, one table per
-- (mechanism x fraction) so that system.part_log / system.parts can be filtered by table name.
--   mut_*  classic mutation   ALTER TABLE ... UPDATE v = v + 1 WHERE ... (mutations_sync = 2: runs until done)
--   ru_*   re-insert          the changed rows again into a ReplacingMergeTree with a higher ver
--   pu_*   patch parts        UPDATE ... SET v = v + 1 WHERE ...  (only where the version has it; last in the file)
-- Each table is one part before the change (OPTIMIZE ... FINAL after the base insert). The changed rows are
-- id = 1000000 (1 row), id % 100 = 0 (1%, spread over every granule) and id % 10 = 0 (10%).
-- "Bytes written" = ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] of the part_log row: bytes the
-- server actually wrote, not the size of the part (a mutation hard-links the columns it does not change).
-- Each scan is SELECT sum(v) (and with FINAL on ReplacingMergeTree, which is what reading it correctly needs),
-- compared with an untouched table of the same size.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.pu_ns;

DROP TABLE IF EXISTS upsert_lab.ctl;

DROP TABLE IF EXISTS upsert_lab.ctl_rmt;

DROP TABLE IF EXISTS upsert_lab.mut_1;

DROP TABLE IF EXISTS upsert_lab.mut_1p;

DROP TABLE IF EXISTS upsert_lab.mut_10p;

DROP TABLE IF EXISTS upsert_lab.ru_1;

DROP TABLE IF EXISTS upsert_lab.ru_1p;

DROP TABLE IF EXISTS upsert_lab.ru_10p;

DROP TABLE IF EXISTS upsert_lab.pu_1;

DROP TABLE IF EXISTS upsert_lab.pu_1p;

DROP TABLE IF EXISTS upsert_lab.pu_10p;

CREATE TABLE upsert_lab.ctl (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.ctl SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.ctl FINAL;

CREATE TABLE upsert_lab.ctl_rmt (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

INSERT INTO upsert_lab.ctl_rmt SELECT number, number, repeat('x', 20), 1 FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.ctl_rmt FINAL;

CREATE TABLE upsert_lab.mut_1 (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.mut_1 SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.mut_1 FINAL;

CREATE TABLE upsert_lab.mut_1p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.mut_1p SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.mut_1p FINAL;

CREATE TABLE upsert_lab.mut_10p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.mut_10p SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.mut_10p FINAL;

-- probe: 04-mut-1
-- Classic mutation of 1 row: the duration is the time until the mutation is done.
ALTER TABLE upsert_lab.mut_1 UPDATE v = v + 1 WHERE id = 1000000 SETTINGS mutations_sync = 2;

-- probe: 04-mut-1p
-- Classic mutation of 1% of the rows: the duration is the time until the mutation is done.
ALTER TABLE upsert_lab.mut_1p UPDATE v = v + 1 WHERE id % 100 = 0 SETTINGS mutations_sync = 2;

-- probe: 04-mut-10p
-- Classic mutation of 10% of the rows: the duration is the time until the mutation is done.
ALTER TABLE upsert_lab.mut_10p UPDATE v = v + 1 WHERE id % 10 = 0 SETTINGS mutations_sync = 2;

CREATE TABLE upsert_lab.ru_1 (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

SYSTEM STOP MERGES upsert_lab.ru_1;

INSERT INTO upsert_lab.ru_1 SELECT number, number, repeat('x', 20), 1 FROM numbers(2000000);

CREATE TABLE upsert_lab.ru_1p (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

SYSTEM STOP MERGES upsert_lab.ru_1p;

INSERT INTO upsert_lab.ru_1p SELECT number, number, repeat('x', 20), 1 FROM numbers(2000000);

CREATE TABLE upsert_lab.ru_10p (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

SYSTEM STOP MERGES upsert_lab.ru_10p;

INSERT INTO upsert_lab.ru_10p SELECT number, number, repeat('x', 20), 1 FROM numbers(2000000);

-- probe: 04-ru-1
-- Re-insert 1 row with ver = 2 (merges stopped, so the old rows are still in the base part).
INSERT INTO upsert_lab.ru_1 SELECT 1000000, 1000001, repeat('x', 20), 2 FROM numbers(1);

-- probe: 04-ru-1p
-- Re-insert 1% of the rows with ver = 2 (merges stopped, so the old rows are still in the base part).
INSERT INTO upsert_lab.ru_1p SELECT number * 100, number * 100 + 1, repeat('x', 20), 2 FROM numbers(20000);

-- probe: 04-ru-10p
-- Re-insert 10% of the rows with ver = 2 (merges stopped, so the old rows are still in the base part).
INSERT INTO upsert_lab.ru_10p SELECT number * 10, number * 10 + 1, repeat('x', 20), 2 FROM numbers(200000);

SYSTEM FLUSH LOGS;

-- probe: 04-mut-1-bytes value
-- bytes written / size of the new part / rows / part_log duration_ms of the MutatePart event(s)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(size_in_bytes) AS part_bytes, sum(rows) AS part_rows, sum(duration_ms) AS ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'mut_1' AND event_type = 'MutatePart';

-- probe: 04-mut-1p-bytes value
-- bytes written / size of the new part / rows / part_log duration_ms of the MutatePart event(s)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(size_in_bytes) AS part_bytes, sum(rows) AS part_rows, sum(duration_ms) AS ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'mut_1p' AND event_type = 'MutatePart';

-- probe: 04-mut-10p-bytes value
-- bytes written / size of the new part / rows / part_log duration_ms of the MutatePart event(s)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(size_in_bytes) AS part_bytes, sum(rows) AS part_rows, sum(duration_ms) AS ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'mut_10p' AND event_type = 'MutatePart';

-- probe: 04-ru-1-bytes value
-- bytes written / rows / part_log duration_ms of the second INSERT (the newest NewPart)
SELECT ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, rows, duration_ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'ru_1' AND event_type = 'NewPart'
ORDER BY event_time_microseconds DESC LIMIT 1;

-- probe: 04-ru-1p-bytes value
-- bytes written / rows / part_log duration_ms of the second INSERT (the newest NewPart)
SELECT ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, rows, duration_ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'ru_1p' AND event_type = 'NewPart'
ORDER BY event_time_microseconds DESC LIMIT 1;

-- probe: 04-ru-10p-bytes value
-- bytes written / rows / part_log duration_ms of the second INSERT (the newest NewPart)
SELECT ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, rows, duration_ms
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'ru_10p' AND event_type = 'NewPart'
ORDER BY event_time_microseconds DESC LIMIT 1;

-- probe: 04-scan-ctl repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.ctl;

-- probe: 04-scan-ctl-rmt-final repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.ctl_rmt FINAL;

-- probe: 04-scan-mut-1 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.mut_1;

-- probe: 04-scan-mut-1p repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.mut_1p;

-- probe: 04-scan-mut-10p repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.mut_10p;

-- probe: 04-scan-ru-1-plain repeat=5 value
-- Wrong answer on purpose: without FINAL the re-written keys are counted twice.
SELECT sum(v) AS s FROM upsert_lab.ru_1;

-- probe: 04-scan-ru-1-final repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.ru_1 FINAL;

-- probe: 04-scan-ru-1p-plain repeat=5 value
-- Wrong answer on purpose: without FINAL the re-written keys are counted twice.
SELECT sum(v) AS s FROM upsert_lab.ru_1p;

-- probe: 04-scan-ru-1p-final repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.ru_1p FINAL;

-- probe: 04-scan-ru-10p-plain repeat=5 value
-- Wrong answer on purpose: without FINAL the re-written keys are counted twice.
SELECT sum(v) AS s FROM upsert_lab.ru_10p;

-- probe: 04-scan-ru-10p-final repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.ru_10p FINAL;

-- Patch parts: the table needs both block columns; the version decides what else (see the settings table).

CREATE TABLE upsert_lab.pu_1 (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.pu_1 SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.pu_1 FINAL;

SYSTEM STOP MERGES upsert_lab.pu_1;

CREATE TABLE upsert_lab.pu_1p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.pu_1p SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.pu_1p FINAL;

SYSTEM STOP MERGES upsert_lab.pu_1p;

CREATE TABLE upsert_lab.pu_10p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.pu_10p SELECT number, number, repeat('x', 20) FROM numbers(2000000);

OPTIMIZE TABLE upsert_lab.pu_10p FINAL;

SYSTEM STOP MERGES upsert_lab.pu_10p;

-- probe: 04-pu-1
-- Patch-part UPDATE of 1 row (merges stopped, so the patch stays a patch part).
UPDATE upsert_lab.pu_1 SET v = v + 1 WHERE id = 1000000 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 04-pu-1p
-- Patch-part UPDATE of 1% of the rows (merges stopped, so the patch stays a patch part).
UPDATE upsert_lab.pu_1p SET v = v + 1 WHERE id % 100 = 0 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 04-pu-10p
-- Patch-part UPDATE of 10% of the rows (merges stopped, so the patch stays a patch part).
UPDATE upsert_lab.pu_10p SET v = v + 1 WHERE id % 10 = 0 SETTINGS allow_experimental_lightweight_update = 1;

SYSTEM FLUSH LOGS;

-- probe: 04-pu-1-bytes value
-- bytes written / rows / size_in_bytes of the patch part(s), from part_log
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS patch_rows, sum(size_in_bytes) AS patch_bytes
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'pu_1' AND event_type = 'NewPart' AND startsWith(part_name, 'patch-');

-- probe: 04-pu-1-parts value
-- active patch parts / their rows / their bytes in system.parts (a patch part is a part whose name starts with 'patch-')
SELECT count() AS patch_parts, sum(rows) AS patch_rows, sum(bytes_on_disk) AS patch_bytes
FROM system.parts WHERE database = 'upsert_lab' AND table = 'pu_1' AND active AND startsWith(name, 'patch-');

-- probe: 04-pu-1p-bytes value
-- bytes written / rows / size_in_bytes of the patch part(s), from part_log
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS patch_rows, sum(size_in_bytes) AS patch_bytes
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'pu_1p' AND event_type = 'NewPart' AND startsWith(part_name, 'patch-');

-- probe: 04-pu-1p-parts value
-- active patch parts / their rows / their bytes in system.parts (a patch part is a part whose name starts with 'patch-')
SELECT count() AS patch_parts, sum(rows) AS patch_rows, sum(bytes_on_disk) AS patch_bytes
FROM system.parts WHERE database = 'upsert_lab' AND table = 'pu_1p' AND active AND startsWith(name, 'patch-');

-- probe: 04-pu-10p-bytes value
-- bytes written / rows / size_in_bytes of the patch part(s), from part_log
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS patch_rows, sum(size_in_bytes) AS patch_bytes
FROM system.part_log WHERE database = 'upsert_lab' AND table = 'pu_10p' AND event_type = 'NewPart' AND startsWith(part_name, 'patch-');

-- probe: 04-pu-10p-parts value
-- active patch parts / their rows / their bytes in system.parts (a patch part is a part whose name starts with 'patch-')
SELECT count() AS patch_parts, sum(rows) AS patch_rows, sum(bytes_on_disk) AS patch_bytes
FROM system.parts WHERE database = 'upsert_lab' AND table = 'pu_10p' AND active AND startsWith(name, 'patch-');

-- probe: 04-scan-pu-1 repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pu_1;

-- probe: 04-scan-pu-1p repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pu_1p;

-- probe: 04-scan-pu-10p repeat=5 value
SELECT sum(v) AS s FROM upsert_lab.pu_10p;

-- Does the UPDATE need the session setting? Same statement as pu_1 but without a SETTINGS clause.
CREATE TABLE upsert_lab.pu_ns (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.pu_ns SELECT number, number, repeat('x', 20) FROM numbers(100000);

-- probe: 04-pu-no-setting
UPDATE upsert_lab.pu_ns SET v = v + 1 WHERE id = 5;
