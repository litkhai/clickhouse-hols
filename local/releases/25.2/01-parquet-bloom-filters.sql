-- ClickHouse 25.2: Parquet Bloom Filters Test
-- New Feature: Parquet files written by ClickHouse now carry Bloom filters, and
--              reads can push equality predicates down into them.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-02

-- A Bloom filter lets the reader skip a row group that cannot contain the value
-- being searched for. The release notes quote roughly 10% more file size, but
-- the real cost scales with the number of distinct values: this lab uses a
-- million unique keys, the worst case, and measures what that actually costs.

-- Parquet cannot be appended to, so allow re-running this lab over the files a
-- previous run left in user_files.
SET engine_file_truncate_on_insert = 1;

-- ============================================
-- 1. Source Data
-- ============================================

SELECT '========== 1. Source Table ==========';

DROP TABLE IF EXISTS pq_source;

CREATE TABLE pq_source
(
    id       UInt64,
    user_key String,
    region   String,
    amount   Float64
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO pq_source
SELECT
    number,
    concat('user_', toString(number)),
    ['us-east', 'eu-west', 'ap-south', 'sa-east'][number % 4 + 1],
    (number % 997) * 1.5
FROM numbers(1000000);

SELECT count() AS rows, uniqExact(user_key) AS distinct_keys FROM pq_source;

-- ============================================
-- 2. The Write-Side Settings
-- ============================================

SELECT '========== 2. Bloom Filter Write Settings ==========';

SELECT name, value
FROM system.settings
WHERE name LIKE 'output_format_parquet_%bloom_filter%'
ORDER BY name;

-- ============================================
-- 3. Two Files: With and Without
-- ============================================

SELECT '========== 3. Writing Both Variants ==========';

INSERT INTO FUNCTION file('bloom_on.parquet', 'Parquet')
SELECT * FROM pq_source
SETTINGS output_format_parquet_write_bloom_filter = 1;

INSERT INTO FUNCTION file('bloom_off.parquet', 'Parquet')
SELECT * FROM pq_source
SETTINGS output_format_parquet_write_bloom_filter = 0;

SELECT 'both files written' AS status;

-- ============================================
-- 4. What the Filters Cost
-- ============================================

SELECT '========== 4. File Size Difference ==========';

-- user_key is unique across all 1,000,000 rows, so the filters have to encode a
-- million distinct values. Expect a much larger gap here than on data with
-- realistic cardinality.

SELECT DISTINCT _file AS file, formatReadableSize(_size) AS size
FROM file('bloom_o*.parquet', 'Parquet')
ORDER BY file;

-- ============================================
-- 5. The Read-Side Setting
-- ============================================

SELECT '========== 5. Bloom Filter Push-Down ==========';

SELECT name, value, description
FROM system.settings
WHERE name = 'input_format_parquet_bloom_filter_push_down';

-- ============================================
-- 6. A Point Lookup, Both Ways
-- ============================================

SELECT '========== 6. Point Lookup With Push-Down ==========';

SELECT count() AS found, min(amount) AS amount
FROM file('bloom_on.parquet', 'Parquet')
WHERE user_key = 'user_999999'
SETTINGS input_format_parquet_bloom_filter_push_down = 1;

SELECT '========== 6b. The Same Lookup Without It ==========';

SELECT count() AS found, min(amount) AS amount
FROM file('bloom_on.parquet', 'Parquet')
WHERE user_key = 'user_999999'
SETTINGS input_format_parquet_bloom_filter_push_down = 0;

-- ============================================
-- 7. A File With No Filters to Push Into
-- ============================================

SELECT '========== 7. Push-Down Against bloom_off.parquet ==========';

-- The setting is harmless here: with no filters in the file there is nothing to
-- consult, and the reader falls back to scanning.
SELECT count() AS found
FROM file('bloom_off.parquet', 'Parquet')
WHERE user_key = 'user_999999'
SETTINGS input_format_parquet_bloom_filter_push_down = 1;

-- ============================================
-- 8. Where Bloom Filters Do Not Help
-- ============================================

SELECT '========== 8. Range and Low-Cardinality Predicates ==========';

-- A Bloom filter answers "is this exact value absent?" — it cannot answer a
-- range question, and it is pointless on a column where every row group holds
-- every value.
SELECT count() AS rows_in_range
FROM file('bloom_on.parquet', 'Parquet')
WHERE amount BETWEEN 100 AND 200
SETTINGS input_format_parquet_bloom_filter_push_down = 1;

SELECT region, count() AS rows
FROM file('bloom_on.parquet', 'Parquet')
GROUP BY region
ORDER BY region
SETTINGS input_format_parquet_bloom_filter_push_down = 1;

-- ============================================
-- 9. Filter Precision
-- ============================================

SELECT '========== 9. bits_per_value Controls False Positives ==========';

-- More bits per value means fewer false positives and a larger file.
INSERT INTO FUNCTION file('bloom_wide.parquet', 'Parquet')
SELECT * FROM pq_source
SETTINGS output_format_parquet_write_bloom_filter = 1,
         output_format_parquet_bloom_filter_bits_per_value = 20;

SELECT DISTINCT _file AS file, formatReadableSize(_size) AS size
FROM file('bloom_*.parquet', 'Parquet')
ORDER BY file;

-- ============================================
-- 10. Correctness Is Unaffected
-- ============================================

SELECT '========== 10. Same Answer Everywhere ==========';

SELECT
    (SELECT count() FROM file('bloom_on.parquet',  'Parquet') WHERE user_key = 'user_500000') AS with_filters,
    (SELECT count() FROM file('bloom_off.parquet', 'Parquet') WHERE user_key = 'user_500000') AS without_filters,
    with_filters = without_filters AS identical;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS pq_source;
-- The parquet files stay in user_files; remove with
--   docker exec clickhouse-25-2 rm /var/lib/clickhouse/user_files/bloom_*.parquet

SELECT '========== Test Complete ==========';
SELECT 'Bloom filters buy row-group skipping on equality; their cost scales with distinct values.' AS summary;
