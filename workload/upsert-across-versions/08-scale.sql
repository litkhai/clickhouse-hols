-- settings: enable_lightweight_update, apply_patch_parts, enable_block_number_column, enable_block_offset_column
-- The read-side cost of each mechanism at a size where a scan takes long enough to measure: 20M rows
-- (10x file 04), 1% and 10% changed (id % 100 = 0, id % 10 = 0; no 1-row case), one table per
-- (mechanism x fraction), the same shapes as file 04:
--   s_mut_*  classic ALTER TABLE ... UPDATE ... mutations_sync = 2
--   s_pu_*   patch-part UPDATE (table with enable_block_number_column / enable_block_offset_column; merges stopped)
--   s_ru_*   re-insert into a ReplacingMergeTree with a higher ver, read with FINAL (merges stopped)
--   s_ctl, s_ctl_rmt   untouched MergeTree, and untouched ReplacingMergeTree read with FINAL
-- Every table is one part before the change (OPTIMIZE ... FINAL after the base insert).
-- Reads: a full scan (a hash of v and s and uniq(v), so that the work is CPU, not only I/O) and a 100,000-row range on the
-- sort key. Each read runs 5 times; the update itself runs once; bytes written come from system.part_log.

CREATE DATABASE IF NOT EXISTS upsert_lab;

DROP TABLE IF EXISTS upsert_lab.s_ctl;

DROP TABLE IF EXISTS upsert_lab.s_ctl_rmt;

DROP TABLE IF EXISTS upsert_lab.s_mut_1p;

DROP TABLE IF EXISTS upsert_lab.s_mut_10p;

DROP TABLE IF EXISTS upsert_lab.s_ru_1p;

DROP TABLE IF EXISTS upsert_lab.s_ru_10p;

DROP TABLE IF EXISTS upsert_lab.s_pu_1p;

DROP TABLE IF EXISTS upsert_lab.s_pu_10p;

CREATE TABLE upsert_lab.s_ctl (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.s_ctl SELECT number, number, repeat('x', 20) FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_ctl FINAL;

CREATE TABLE upsert_lab.s_ctl_rmt (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

INSERT INTO upsert_lab.s_ctl_rmt SELECT number, number, repeat('x', 20), 1 FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_ctl_rmt FINAL;

CREATE TABLE upsert_lab.s_mut_1p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.s_mut_1p SELECT number, number, repeat('x', 20) FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_mut_1p FINAL;

CREATE TABLE upsert_lab.s_mut_10p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;

INSERT INTO upsert_lab.s_mut_10p SELECT number, number, repeat('x', 20) FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_mut_10p FINAL;

-- probe: 08-mut-1p
-- Classic mutation of 1% of the rows.
ALTER TABLE upsert_lab.s_mut_1p UPDATE v = v + 1 WHERE id % 100 = 0 SETTINGS mutations_sync = 2;

-- probe: 08-mut-10p
-- Classic mutation of 10% of the rows.
ALTER TABLE upsert_lab.s_mut_10p UPDATE v = v + 1 WHERE id % 10 = 0 SETTINGS mutations_sync = 2;

CREATE TABLE upsert_lab.s_ru_1p (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

INSERT INTO upsert_lab.s_ru_1p SELECT number, number, repeat('x', 20), 1 FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_ru_1p FINAL;

SYSTEM STOP MERGES upsert_lab.s_ru_1p;

CREATE TABLE upsert_lab.s_ru_10p (id UInt64, v UInt64, s String, ver UInt32) ENGINE = ReplacingMergeTree(ver) ORDER BY id;

INSERT INTO upsert_lab.s_ru_10p SELECT number, number, repeat('x', 20), 1 FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_ru_10p FINAL;

SYSTEM STOP MERGES upsert_lab.s_ru_10p;

-- probe: 08-ru-1p
-- Re-insert 1% of the rows with ver = 2.
INSERT INTO upsert_lab.s_ru_1p SELECT number * 100, number * 100 + 1, repeat('x', 20), 2 FROM numbers(200000);

-- probe: 08-ru-10p
-- Re-insert 10% of the rows with ver = 2.
INSERT INTO upsert_lab.s_ru_10p SELECT number * 10, number * 10 + 1, repeat('x', 20), 2 FROM numbers(2000000);

CREATE TABLE upsert_lab.s_pu_1p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.s_pu_1p SELECT number, number, repeat('x', 20) FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_pu_1p FINAL;

SYSTEM STOP MERGES upsert_lab.s_pu_1p;

CREATE TABLE upsert_lab.s_pu_10p (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO upsert_lab.s_pu_10p SELECT number, number, repeat('x', 20) FROM numbers(20000000);

OPTIMIZE TABLE upsert_lab.s_pu_10p FINAL;

SYSTEM STOP MERGES upsert_lab.s_pu_10p;

-- probe: 08-pu-1p
-- Patch-part UPDATE of 1% of the rows.
UPDATE upsert_lab.s_pu_1p SET v = v + 1 WHERE id % 100 = 0 SETTINGS allow_experimental_lightweight_update = 1;

-- probe: 08-pu-10p
-- Patch-part UPDATE of 10% of the rows.
UPDATE upsert_lab.s_pu_10p SET v = v + 1 WHERE id % 10 = 0 SETTINGS allow_experimental_lightweight_update = 1;

SYSTEM FLUSH LOGS;

-- probe: 08-mut-1p-bytes value
-- bytes written / new part rows / events
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS part_rows, count() AS events
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_mut_1p' AND event_type = 'MutatePart';

-- probe: 08-ru-1p-bytes value
-- bytes written / rows of the second INSERT (the newest NewPart)
SELECT ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, rows
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_ru_1p' AND event_type = 'NewPart'
ORDER BY event_time_microseconds DESC LIMIT 1;

-- probe: 08-pu-1p-bytes value
-- bytes written / rows of the patch part(s)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS patch_rows
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_pu_1p' AND event_type = 'NewPart' AND startsWith(part_name, 'patch-');

-- probe: 08-mut-10p-bytes value
-- bytes written / new part rows / events
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS part_rows, count() AS events
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_mut_10p' AND event_type = 'MutatePart';

-- probe: 08-ru-10p-bytes value
-- bytes written / rows of the second INSERT (the newest NewPart)
SELECT ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, rows
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_ru_10p' AND event_type = 'NewPart'
ORDER BY event_time_microseconds DESC LIMIT 1;

-- probe: 08-pu-10p-bytes value
-- bytes written / rows of the patch part(s)
SELECT sum(ProfileEvents['WriteBufferFromFileDescriptorWriteBytes']) AS written_bytes, sum(rows) AS patch_rows
FROM system.part_log WHERE database = 'upsert_lab' AND table = 's_pu_10p' AND event_type = 'NewPart' AND startsWith(part_name, 'patch-');

-- probe: 08-scan-ctl repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ctl;

-- probe: 08-scan-ctl-rmt repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ctl_rmt FINAL;

-- probe: 08-scan-mut-1p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_mut_1p;

-- probe: 08-scan-mut-10p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_mut_10p;

-- probe: 08-scan-ru-1p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ru_1p FINAL;

-- probe: 08-scan-ru-10p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ru_10p FINAL;

-- probe: 08-scan-pu-1p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_pu_1p;

-- probe: 08-scan-pu-10p repeat=5 value
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_pu_10p;

-- probe: 08-range-ctl repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_ctl WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-ctl-rmt repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_ctl_rmt FINAL WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-mut-1p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_mut_1p WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-mut-10p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_mut_10p WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-ru-1p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_ru_1p FINAL WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-ru-10p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_ru_10p FINAL WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-pu-1p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_pu_1p WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-range-pu-10p repeat=5 value
SELECT sum(cityHash64(v)) AS h, count() AS n FROM upsert_lab.s_pu_10p WHERE id BETWEEN 10000000 AND 10099999;

-- probe: 08-ru-1p-plain repeat=5 value
-- Without FINAL: fast and wrong (the re-written keys are counted twice).
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ru_1p;

-- probe: 08-ru-10p-plain repeat=5 value
-- Without FINAL: fast and wrong (the re-written keys are counted twice).
SELECT sum(sipHash64(v, s)) AS h, uniq(v) AS u FROM upsert_lab.s_ru_10p;
