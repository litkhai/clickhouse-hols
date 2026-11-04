-- ClickHouse 25.7 Feature: Bulk UPDATE on patch parts vs ALTER TABLE ... UPDATE
-- Purpose: run the same five bulk updates twice on identical tables, once as
--          `UPDATE ... SET ... WHERE` (patch parts) and once as `ALTER TABLE ... UPDATE`
--          (mutations that rewrite parts), then read the time and the bytes written for
--          each from this run's system.query_log and system.part_log.
-- Data: 3,000,000 rows per table. A small, single-node, local run: the numbers describe
--       this data on this server only; they are not a general speed-up factor.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-07
-- Needs allow_experimental_lightweight_update = 1 and, on the table,
-- enable_block_number_column = 1, enable_block_offset_column = 1 (see 01-sql-update-delete).

SET allow_experimental_lightweight_update = 1;

DROP TABLE IF EXISTS products_patch;
DROP TABLE IF EXISTS products_alter;
DROP TABLE IF EXISTS bulk_marker;

-- Everything measured below is read from the log after this instant.
CREATE TABLE bulk_marker (t DateTime64(6)) ENGINE = Memory;
INSERT INTO bulk_marker SELECT now64(6);

CREATE TABLE products_patch
(
    product_id     UInt64,
    sku            String,
    category       LowCardinality(String),
    current_price  Decimal(10, 2),
    original_price Decimal(10, 2),
    stock_quantity UInt32,
    last_updated   DateTime,
    is_active      UInt8
)
ENGINE = MergeTree
ORDER BY product_id
SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

CREATE TABLE products_alter AS products_patch ENGINE = MergeTree ORDER BY product_id
SETTINGS enable_block_number_column = 1, enable_block_offset_column = 1;

INSERT INTO products_patch
SELECT
    number,
    concat('SKU-', toString(number)),
    ['Electronics', 'Clothing', 'Books', 'Home', 'Sports', 'Toys', 'Food', 'Beauty'][1 + (number % 8)],
    round(10 + (number % 990), 2),
    round(10 + (number % 990), 2),
    100 + (number % 900),
    toDateTime('2025-07-01 00:00:00'),
    1
FROM numbers(3000000);

INSERT INTO products_alter SELECT * FROM products_patch;

SELECT '=== Dataset: 3,000,000 products per table, identical ===' AS title;
SELECT
    (SELECT count() FROM products_patch) AS patch_rows,
    (SELECT count() FROM products_alter) AS alter_rows,
    (SELECT round(avg(current_price), 2) FROM products_patch) AS avg_price;

-- The same five updates, first as UPDATE (log_comment bulk-patch), then as ALTER ... UPDATE
-- (log_comment bulk-alter). Row counts per update are in section 3.

SET log_comment = 'bulk-patch';

UPDATE products_patch SET current_price = round(current_price * 1.15, 2) WHERE category = 'Electronics';
UPDATE products_patch SET current_price = round(current_price * 0.70, 2) WHERE category IN ('Clothing', 'Books', 'Toys');
UPDATE products_patch SET stock_quantity = stock_quantity + 500 WHERE current_price < 50 AND stock_quantity < 300;
UPDATE products_patch SET current_price = round(current_price * 0.90, 2), stock_quantity = stock_quantity - 100, is_active = 0
    WHERE stock_quantity > 800 AND current_price > 500;
UPDATE products_patch SET original_price = current_price, last_updated = toDateTime('2025-07-24 00:00:00') WHERE is_active = 1;

SET log_comment = 'bulk-alter';

ALTER TABLE products_alter UPDATE current_price = round(current_price * 1.15, 2) WHERE category = 'Electronics' SETTINGS mutations_sync = 2;
ALTER TABLE products_alter UPDATE current_price = round(current_price * 0.70, 2) WHERE category IN ('Clothing', 'Books', 'Toys') SETTINGS mutations_sync = 2;
ALTER TABLE products_alter UPDATE stock_quantity = stock_quantity + 500 WHERE current_price < 50 AND stock_quantity < 300 SETTINGS mutations_sync = 2;
ALTER TABLE products_alter UPDATE current_price = round(current_price * 0.90, 2), stock_quantity = stock_quantity - 100, is_active = 0
    WHERE stock_quantity > 800 AND current_price > 500 SETTINGS mutations_sync = 2;
ALTER TABLE products_alter UPDATE original_price = current_price, last_updated = toDateTime('2025-07-24 00:00:00') WHERE is_active = 1 SETTINGS mutations_sync = 2;

SET log_comment = '';

-- 1. Same data afterwards?
SELECT '=== 1. Both tables hold the same data (row-hash sum; patches applied on read) ===' AS title;
SELECT
    (SELECT sum(cityHash64(*)) FROM products_patch) AS hash_patch,
    (SELECT sum(cityHash64(*)) FROM products_alter) AS hash_alter,
    hash_patch = hash_alter AS identical;

SELECT '--- what the updates did' AS step;
SELECT
    countIf(is_active = 0) AS deactivated,
    round(avgIf(current_price, category = 'Electronics'), 2) AS electronics_avg_price,
    round(avgIf(current_price, category = 'Clothing'), 2) AS clothing_avg_price,
    countIf(original_price = current_price) AS prices_synced
FROM products_patch;

-- 2. What is on disk
SELECT '=== 2. Parts: patch parts next to the data parts vs rewritten parts ===' AS title;
SELECT table, countIf(name LIKE 'patch-%') AS patch_parts, countIf(name NOT LIKE 'patch-%') AS data_parts,
       sumIf(rows, name LIKE 'patch-%') AS patch_rows, sumIf(bytes_on_disk, name LIKE 'patch-%') AS patch_bytes,
       sumIf(bytes_on_disk, name NOT LIKE 'patch-%') AS data_bytes
FROM system.parts
WHERE database = currentDatabase() AND table IN ('products_patch', 'products_alter') AND active
GROUP BY table ORDER BY table;

-- 3. Time and bytes written, from this run
SELECT '=== 3. Time and bytes written for the five updates ===' AS title;
SYSTEM FLUSH LOGS;

SELECT '--- wall time per statement (system.query_log, query_duration_ms; the ALTERs waited with mutations_sync = 2)' AS step;
SELECT
    if(log_comment = 'bulk-patch', 'UPDATE', 'ALTER TABLE ... UPDATE') AS statement,
    count() AS statements,
    sum(query_duration_ms) AS total_ms,
    max(query_duration_ms) AS slowest_ms
FROM system.query_log
WHERE type = 'QueryFinish' AND query_kind IN ('Update', 'Alter') AND log_comment IN ('bulk-patch', 'bulk-alter')
  AND event_time_microseconds >= (SELECT max(t) FROM bulk_marker)
GROUP BY log_comment ORDER BY log_comment DESC;

SELECT '--- what was written (system.part_log): new patch parts vs mutated parts' AS step;
SELECT
    if(table = 'products_patch', 'UPDATE', 'ALTER TABLE ... UPDATE') AS statement,
    count() AS new_parts,
    sum(rows) AS rows_written,
    sum(size_in_bytes) AS bytes_on_disk,
    sum(bytes_uncompressed) AS bytes_uncompressed,
    sum(duration_ms) AS part_build_ms
FROM system.part_log
WHERE database = currentDatabase() AND table IN ('products_patch', 'products_alter')
  AND ((event_type = 'NewPart' AND part_name LIKE 'patch-%') OR event_type = 'MutatePart')
  AND event_time_microseconds >= (SELECT max(t) FROM bulk_marker)
GROUP BY table ORDER BY table DESC;
-- bytes_on_disk of a mutated part is the whole new part (unchanged columns may be hard-linked), so it
-- is an upper bound for what the mutation wrote; bytes_uncompressed is what the part build produced.

-- 4. Folding the patches into the data
SELECT '=== 4. OPTIMIZE ... FINAL on the patch table ===' AS title;
OPTIMIZE TABLE products_patch FINAL;
SELECT
    (SELECT sum(cityHash64(*)) FROM products_patch SETTINGS apply_patch_parts = 0) AS hash_patch_no_patches,
    (SELECT sum(cityHash64(*)) FROM products_alter) AS hash_alter,
    hash_patch_no_patches = hash_alter AS merged_part_holds_the_updates;

-- Cleanup (commented out for inspection)
-- DROP TABLE products_patch; DROP TABLE products_alter; DROP TABLE bulk_marker;

SELECT '✅ Bulk UPDATE test complete' AS status;
