-- ClickHouse 25.1: Table-Level Automatic MinMax Indices Test
-- New Feature: add_minmax_index_for_numeric_columns / add_minmax_index_for_string_columns
--              build a minmax skip index on every suitable column, without naming them.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-01

-- A minmax index is cheap and helps any range or equality predicate on a
-- correlated column. Declaring one per column by hand is tedious on a wide
-- table, so 25.1 turns it into a table setting.

-- ============================================
-- 1. Baseline: A Table With No Skip Indices
-- ============================================

SELECT '========== 1. Baseline Table (no skip indices) ==========';

DROP TABLE IF EXISTS orders_plain;

CREATE TABLE orders_plain
(
    order_id    UInt64,
    customer_id UInt32,
    amount      Float64,
    quantity    UInt32,
    status      String,
    region      String
)
ENGINE = MergeTree
ORDER BY order_id;

INSERT INTO orders_plain
SELECT
    number,
    number % 50000,
    (number % 1000) * 1.25,
    number % 20,
    ['new', 'paid', 'shipped', 'closed'][number % 4 + 1],
    ['us-east', 'eu-west', 'ap-south'][number % 3 + 1]
FROM numbers(500000);

SELECT count() AS indices FROM system.data_skipping_indices WHERE table = 'orders_plain';

-- ============================================
-- 2. The Same Table With Automatic Numeric Indices
-- ============================================

SELECT '========== 2. add_minmax_index_for_numeric_columns ==========';

DROP TABLE IF EXISTS orders_auto;

CREATE TABLE orders_auto
(
    order_id    UInt64,
    customer_id UInt32,
    amount      Float64,
    quantity    UInt32,
    status      String,
    region      String
)
ENGINE = MergeTree
ORDER BY order_id
SETTINGS add_minmax_index_for_numeric_columns = 1;

INSERT INTO orders_auto SELECT * FROM orders_plain;

-- One index per numeric column, named auto_minmax_index_<column>.
SELECT name, type_full, expr, granularity
FROM system.data_skipping_indices
WHERE table = 'orders_auto'
ORDER BY name;

-- ============================================
-- 3. String Columns Are a Separate Switch
-- ============================================

SELECT '========== 3. add_minmax_index_for_string_columns ==========';

DROP TABLE IF EXISTS orders_auto_str;

CREATE TABLE orders_auto_str
(
    order_id    UInt64,
    customer_id UInt32,
    amount      Float64,
    status      String,
    region      String
)
ENGINE = MergeTree
ORDER BY order_id
SETTINGS add_minmax_index_for_numeric_columns = 1,
         add_minmax_index_for_string_columns = 1;

INSERT INTO orders_auto_str
SELECT order_id, customer_id, amount, status, region FROM orders_plain;

SELECT name, expr FROM system.data_skipping_indices
WHERE table = 'orders_auto_str'
ORDER BY name;

-- ============================================
-- 4. What the Index Does to a Query
-- ============================================

SELECT '========== 4. Granules Read, With and Without ==========';

-- amount correlates with order_id here, so its minmax index prunes well.
SELECT 'without automatic indices' AS variant;
EXPLAIN indexes = 1 SELECT count() FROM orders_plain WHERE amount BETWEEN 1200 AND 1210;

SELECT 'with automatic indices' AS variant;
EXPLAIN indexes = 1 SELECT count() FROM orders_auto WHERE amount BETWEEN 1200 AND 1210;

-- ============================================
-- 5. Same Answer Either Way
-- ============================================

SELECT '========== 5. Results Are Identical ==========';

SELECT
    (SELECT count() FROM orders_plain WHERE amount BETWEEN 1200 AND 1210) AS plain,
    (SELECT count() FROM orders_auto  WHERE amount BETWEEN 1200 AND 1210) AS auto_indexed,
    plain = auto_indexed AS same;

-- ============================================
-- 6. A Column the Index Cannot Help
-- ============================================

SELECT '========== 6. Uncorrelated Column ==========';

-- quantity cycles every 20 rows, so every granule holds every value and the
-- index prunes nothing. The setting builds an index regardless: it is a
-- convenience, not a judgement about usefulness.
EXPLAIN indexes = 1 SELECT count() FROM orders_auto WHERE quantity = 7;

-- ============================================
-- 7. Index Storage Cost
-- ============================================

SELECT '========== 7. What the Indices Cost ==========';

SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes)) AS index_size
FROM system.data_skipping_indices
WHERE table IN ('orders_auto', 'orders_auto_str')
GROUP BY table
ORDER BY table;

SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) AS table_size
FROM system.parts
WHERE table IN ('orders_plain', 'orders_auto', 'orders_auto_str') AND active
GROUP BY table
ORDER BY table;

-- ============================================
-- 8. It Is a Create-Time Setting
-- ============================================

SELECT '========== 8. It Is a Create-Time Setting ==========';

-- The setting is read-only once the table exists: ALTER TABLE ... MODIFY
-- SETTING add_minmax_index_for_numeric_columns fails with READONLY_SETTING.
-- An existing table therefore needs the indices added the explicit way.
ALTER TABLE orders_plain ADD INDEX idx_amount amount TYPE minmax GRANULARITY 1;
ALTER TABLE orders_plain MATERIALIZE INDEX idx_amount SETTINGS mutations_sync = 2;

SELECT name, type_full, expr FROM system.data_skipping_indices WHERE table = 'orders_plain';

-- The setting is visible in the DDL of the tables that were created with it.
SELECT name, engine_full LIKE '%add_minmax_index_for_numeric_columns = 1%' AS created_with_setting
FROM system.tables
WHERE name IN ('orders_plain', 'orders_auto')
ORDER BY name;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS orders_plain;
-- DROP TABLE IF EXISTS orders_auto;
-- DROP TABLE IF EXISTS orders_auto_str;

SELECT '========== Test Complete ==========';
SELECT 'One table setting replaces an INDEX clause per column.' AS summary;
