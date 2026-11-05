-- 03: why the classic ALTER UPDATE of 1% of 20M rows wrote about 79 MB on 24.8 to 26.8 and 20 MB on 26.10
-- (file 08, item 3 of README 'Explained'). The s_mut_1p table of file 08, twice:
--   pc_codec_default  no codec anywhere: the build's built-in default codec
--   pc_codec_lz4      the table setting default_compression_codec = 'LZ4'
-- The codec is chosen when a part is written, so OPTIMIZE ... FINAL already decides it, before the mutation.
-- Run: clickhouse-client --multiquery < explain/03-default-codec.sql   (about 1 GB of RAM, 1 to 2 minutes)

CREATE DATABASE IF NOT EXISTS upsert_explain;

DROP TABLE IF EXISTS upsert_explain.pc_codec_default;
DROP TABLE IF EXISTS upsert_explain.pc_codec_lz4;

CREATE TABLE upsert_explain.pc_codec_default (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id;
INSERT INTO upsert_explain.pc_codec_default SELECT number, number, repeat('x', 20) FROM numbers(20000000);
OPTIMIZE TABLE upsert_explain.pc_codec_default FINAL;

CREATE TABLE upsert_explain.pc_codec_lz4 (id UInt64, v UInt64, s String) ENGINE = MergeTree ORDER BY id SETTINGS default_compression_codec = 'LZ4';
INSERT INTO upsert_explain.pc_codec_lz4 SELECT number, number, repeat('x', 20) FROM numbers(20000000);
OPTIMIZE TABLE upsert_explain.pc_codec_lz4 FINAL;

-- before the mutation: the merged part's codec and size
SELECT table, name, default_compression_codec, bytes_on_disk
FROM system.parts WHERE database = 'upsert_explain' AND table IN ('pc_codec_default', 'pc_codec_lz4') AND active
ORDER BY table;

ALTER TABLE upsert_explain.pc_codec_default UPDATE v = v + 1 WHERE id % 100 = 0 SETTINGS mutations_sync = 2;
ALTER TABLE upsert_explain.pc_codec_lz4 UPDATE v = v + 1 WHERE id % 100 = 0 SETTINGS mutations_sync = 2;

SYSTEM FLUSH LOGS;

-- what the mutation wrote (the same measure as file 08) and the codec of the part it wrote
SELECT p.table, p.part_name, p.ProfileEvents['WriteBufferFromFileDescriptorWriteBytes'] AS written_bytes, s.default_compression_codec
FROM system.part_log AS p
INNER JOIN system.parts AS s ON s.database = p.database AND s.table = p.table AND s.name = p.part_name
WHERE p.database = 'upsert_explain' AND p.table IN ('pc_codec_default', 'pc_codec_lz4') AND p.event_type = 'MutatePart'
ORDER BY p.table;
