-- ClickHouse 25.2: Backup Database Engine Test
-- New Feature: CREATE DATABASE ... ENGINE = Backup(...) attaches the tables in a
--              backup read-only and instantly, without restoring them.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-02

-- RESTORE copies data back before you can query it. The Backup engine skips the
-- copy: the backup is mounted as a read-only database, so "what did this table
-- look like last Tuesday" is a query rather than a restore job.

-- ============================================
-- 1. Live Tables to Back Up
-- ============================================

SELECT '========== 1. Live Data ==========';

DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS customers;

CREATE TABLE sales
(
    sale_id     UInt64,
    customer_id UInt32,
    sale_date   Date,
    amount      Decimal(10, 2)
)
ENGINE = MergeTree
ORDER BY sale_id;

CREATE TABLE customers
(
    customer_id UInt32,
    name        String,
    tier        String
)
ENGINE = MergeTree
ORDER BY customer_id;

INSERT INTO sales
SELECT
    number,
    number % 1000,
    toDate('2025-01-01') + (number % 60),
    toDecimal64((number % 500) + 10.5, 2)
FROM numbers(50000);

INSERT INTO customers
SELECT number, concat('customer_', toString(number)),
       ['free', 'pro', 'enterprise'][number % 3 + 1]
FROM numbers(1000);

SELECT (SELECT count() FROM sales)      AS sales_rows,
       (SELECT count() FROM customers)  AS customer_rows,
       (SELECT round(sum(amount), 2) FROM sales) AS sales_total;

-- ============================================
-- 2. Take a Backup
-- ============================================

SELECT '========== 2. BACKUP ==========';

-- A relative File() path lands under the server's configured backup directory
-- (/var/lib/clickhouse/backups by default). Absolute paths must be listed in
-- backups.allowed_path or the server rejects them.
--
-- BACKUP refuses to overwrite an existing destination, so the runner removes
-- the directory first to keep this lab re-runnable. Running the SQL by hand
-- needs the same:
--   docker exec clickhouse-25-2 rm -rf /var/lib/clickhouse/backups/snapshot_v1
BACKUP TABLE sales, TABLE customers TO File('snapshot_v1');

-- ============================================
-- 3. Change the Live Data
-- ============================================

SELECT '========== 3. Live Tables Move On ==========';

INSERT INTO sales
SELECT
    100000 + number,
    number % 1000,
    toDate('2025-03-01') + (number % 30),
    toDecimal64((number % 500) + 10.5, 2)
FROM numbers(10000);

ALTER TABLE customers UPDATE tier = 'enterprise' WHERE customer_id < 100 SETTINGS mutations_sync = 2;

SELECT count() AS live_sales_rows FROM sales;
SELECT countIf(tier = 'enterprise') AS live_enterprise_customers FROM customers;

-- ============================================
-- 4. Attach the Backup as a Database
-- ============================================

SELECT '========== 4. Backup Database Engine ==========';

DROP DATABASE IF EXISTS snapshot;

CREATE DATABASE snapshot ENGINE = Backup('default', File('snapshot_v1'));

SHOW TABLES FROM snapshot;

-- ============================================
-- 5. Query the Backup Directly
-- ============================================

SELECT '========== 5. Reading From the Backup ==========';

SELECT count() AS rows_at_backup_time FROM snapshot.sales;
SELECT countIf(tier = 'enterprise') AS enterprise_at_backup_time FROM snapshot.customers;

-- ============================================
-- 6. Comparing Backup With Live
-- ============================================

SELECT '========== 6. Live vs Backup ==========';

SELECT
    (SELECT count() FROM sales)          AS live_rows,
    (SELECT count() FROM snapshot.sales) AS backup_rows,
    live_rows - backup_rows              AS rows_added_since;

SELECT
    (SELECT countIf(tier = 'enterprise') FROM customers)          AS live_enterprise,
    (SELECT countIf(tier = 'enterprise') FROM snapshot.customers) AS backup_enterprise,
    live_enterprise - backup_enterprise                           AS upgraded_since;

-- ============================================
-- 7. Joining Across the Boundary
-- ============================================

SELECT '========== 7. Which Customers Changed Tier ==========';

SELECT
    c.customer_id,
    s.tier AS tier_at_backup,
    c.tier AS tier_now
FROM customers AS c
INNER JOIN snapshot.customers AS s ON c.customer_id = s.customer_id
WHERE c.tier != s.tier
ORDER BY c.customer_id
LIMIT 10;

-- ============================================
-- 8. Aggregating Only the New Rows
-- ============================================

SELECT '========== 8. Sales Added After the Backup ==========';

SELECT
    toStartOfMonth(sale_date) AS month,
    count()                   AS sales,
    round(sum(amount), 2)     AS revenue
FROM sales
WHERE sale_id NOT IN (SELECT sale_id FROM snapshot.sales)
GROUP BY month
ORDER BY month;

-- ============================================
-- 9. It Is Read-Only
-- ============================================

SELECT '========== 9. Read-Only by Construction ==========';

-- Writes to a Backup database are rejected; the engine exists to read a
-- snapshot, not to become one. (Not executed here: a failing statement would
-- abort the rest of the script.)
SELECT 'INSERT INTO snapshot.sales ... is rejected by the engine' AS note;

SELECT name, engine FROM system.databases WHERE name = 'snapshot';

-- ============================================
-- 10. Detaching
-- ============================================

SELECT '========== 10. Dropping the Attached Database ==========';

-- Dropping the database detaches the backup. The backup files themselves are
-- untouched and can be attached again.
DROP DATABASE snapshot;

SELECT count() AS snapshot_databases FROM system.databases WHERE name = 'snapshot';

CREATE DATABASE snapshot ENGINE = Backup('default', File('snapshot_v1'));
SELECT count() AS rows_after_reattach FROM snapshot.sales;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP DATABASE IF EXISTS snapshot;
-- DROP TABLE IF EXISTS sales;
-- DROP TABLE IF EXISTS customers;
-- Backup files remain under /var/lib/clickhouse/backups/snapshot_v1

SELECT '========== Test Complete ==========';
SELECT 'A backup becomes queryable without restoring it.' AS summary;
