-- ClickHouse 26.9 — ZSTD(3) becomes the default compression
--
-- 26.9 changes what ClickHouse compresses with when you do not say. It is
-- listed under backward incompatible changes even though nothing breaks:
-- every compressed frame is self-describing, so old data keeps reading.
--
-- Three separate things changed, and conflating them is how people end up
-- surprised:
--
--   network        client/server and server/server, and HTTP compress=1,
--                  are now ZSTD(3) uniformly
--   MergeTree      column data is size-aware — LZ4 below 100 MB, ZSTD(3) at
--                  or above it, judged by the part size known at write time
--   other streams  StripeLog, the Set and Join engine files, and MergeTree
--                  auxiliary files such as checksums.txt are ZSTD(3) always
--
-- The middle one is the one that matters for storage, and the size rule has a
-- consequence the changelog states but is easy to read past: a plain INSERT
-- does not know how big its part will be, so freshly inserted data is LZ4
-- regardless of size. ZSTD arrives later, when background merges have
-- accumulated enough of it. Section 4 measures exactly that.

SELECT '════════ 1. Network compression ════════' AS section;

SELECT * FROM (
    SELECT '26.9 default   ' AS profile_, getSetting('network_compression_method') AS codec
    UNION ALL
    SELECT 'compatibility 26.8', getSetting('network_compression_method') SETTINGS compatibility = '26.8'
    UNION ALL
    SELECT 'compatibility 25.1', getSetting('network_compression_method') SETTINGS compatibility = '25.1'
) ORDER BY profile_;

-- Expected: ZSTD, LZ4, LZ4. The compatibility setting does roll the network
-- side back. Section 5 shows that it does not roll the column data back.

SELECT '════════ 2. A small table: the default is still LZ4 ════════' AS section;

DROP TABLE IF EXISTS c_default;
DROP TABLE IF EXISTS c_lz4;
DROP TABLE IF EXISTS c_zstd;

CREATE TABLE c_default (s String,               n UInt64)               ENGINE = MergeTree ORDER BY n;
CREATE TABLE c_lz4     (s String CODEC(LZ4),    n UInt64 CODEC(LZ4))    ENGINE = MergeTree ORDER BY n;
CREATE TABLE c_zstd    (s String CODEC(ZSTD(3)), n UInt64 CODEC(ZSTD(3))) ENGINE = MergeTree ORDER BY n;

INSERT INTO c_default
SELECT concat('service=checkout env=prod region=ap-northeast-2 user=', toString(number % 5000)), number
FROM numbers(2000000);
INSERT INTO c_lz4  SELECT * FROM c_default;
INSERT INTO c_zstd SELECT * FROM c_default;

OPTIMIZE TABLE c_default FINAL;
OPTIMIZE TABLE c_lz4     FINAL;
OPTIMIZE TABLE c_zstd    FINAL;

SELECT table,
       formatReadableSize(sum(data_compressed_bytes))   AS compressed,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
       round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts_columns
WHERE table IN ('c_default', 'c_lz4', 'c_zstd') AND active AND column = 's'
GROUP BY table ORDER BY table;

-- Expected: c_default and c_lz4 land on the same ratio, about 8x. c_zstd is
-- about 40x on this data. The table is ~17 MB, well under 100 MB, so the
-- size-aware default picked LZ4 — the new default did nothing here.

SELECT '════════ 3. What the part metadata says ════════' AS section;

-- default_compression_codec reports the table's declared default, not the
-- codec the size rule actually chose. It says LZ4 for all three, including
-- c_zstd where every column carries an explicit CODEC(ZSTD(3)). Measure the
-- ratio; do not trust this column to tell you what is on disk.

SELECT table, name AS part, default_compression_codec, formatReadableSize(bytes_on_disk) AS on_disk
FROM system.parts
WHERE table IN ('c_default', 'c_lz4', 'c_zstd') AND active
ORDER BY table;

SELECT '════════ 4. Crossing 100 MB: the default flips on merge ════════' AS section;

DROP TABLE IF EXISTS c_big;
CREATE TABLE c_big (s String, n UInt64) ENGINE = MergeTree ORDER BY n;

-- Two inserts of 6.5M rows. Each settles at roughly 56 MB on disk, so neither
-- part on its own reaches the threshold.
INSERT INTO c_big
SELECT concat('service=checkout env=prod region=ap-northeast-2 user=', toString(number % 5000)), number
FROM numbers(6500000);
INSERT INTO c_big
SELECT concat('service=search env=prod region=us-east-1 user=', toString(number % 5000)), number + 6500000
FROM numbers(6500000);

SELECT 'before merge' AS stage,
       formatReadableSize(sum(data_compressed_bytes)) AS compressed,
       round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts_columns WHERE table = 'c_big' AND active AND column = 's';

-- Merging them gives source parts of ~112 MB, which is over the threshold, so
-- the merged part is written with ZSTD(3).
OPTIMIZE TABLE c_big FINAL;

SELECT 'after merge' AS stage,
       formatReadableSize(sum(data_compressed_bytes)) AS compressed,
       round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts_columns WHERE table = 'c_big' AND active AND column = 's';

-- Expected: about 8x before, about 40x after, and the compressed size falls by
-- roughly a factor of five even though no rows were removed. Nothing about the
-- table definition changed — only the size of the parts going into the merge.
--
-- The operational reading: on a fresh cluster your newest data is LZ4 and your
-- settled data is ZSTD(3), and disk usage keeps dropping behind you as merges
-- catch up. Capacity planning off a day-one measurement will overshoot.

SELECT '════════ 5. compatibility does not roll the column data back ════════' AS section;

DROP TABLE IF EXISTS c_compat;
CREATE TABLE c_compat (s String, n UInt64) ENGINE = MergeTree ORDER BY n;
INSERT INTO c_compat
SELECT concat('service=checkout env=prod region=ap-northeast-2 user=', toString(number % 5000)), number
FROM numbers(6500000);
INSERT INTO c_compat
SELECT concat('service=search env=prod region=us-east-1 user=', toString(number % 5000)), number + 6500000
FROM numbers(6500000);

OPTIMIZE TABLE c_compat FINAL SETTINGS compatibility = '26.8';

SELECT round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio_under_compat_26_8
FROM system.parts_columns WHERE table = 'c_compat' AND active AND column = 's';

-- Still ~40x. compatibility covers the network codec and a long list of other
-- settings, but the MergeTree column default is not one of them. To pin column
-- data to LZ4 you set CODEC(LZ4) on the column or the table, or change the
-- server-level <compression> default. Section 2's c_lz4 is that first option.

SELECT '════════ 6. Marks and the primary key were already ZSTD(3) ════════' AS section;

-- Worth knowing before you go looking for a regression: these two have
-- defaulted to ZSTD(3) for several releases. They are not part of this change.

SELECT name, value FROM system.merge_tree_settings
WHERE name IN ('marks_compression_codec', 'primary_key_compression_codec',
               'compress_marks', 'compress_primary_key')
ORDER BY name;

-- Cleanup left commented so you can keep poking at the tables.
-- DROP TABLE IF EXISTS c_default;
-- DROP TABLE IF EXISTS c_lz4;
-- DROP TABLE IF EXISTS c_zstd;
-- DROP TABLE IF EXISTS c_big;
-- DROP TABLE IF EXISTS c_compat;
