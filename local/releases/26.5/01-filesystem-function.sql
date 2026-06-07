-- ClickHouse 26.5: filesystem Table Function Test
-- New Feature: filesystem('path') exposes directory structure, file metadata, and contents as a SQL table
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/53610

-- Note: filesystem() reads relative to user_files (default /var/lib/clickhouse/user_files).
-- This script first creates a few sample files using INSERT INTO FUNCTION file(),
-- then queries them with filesystem().

-- ============================================
-- 1. Create Sample Files via file() Table Function
-- ============================================

SELECT '========== 1. Creating Sample Files in user_files ==========';

-- Three CSV files of different sizes
INSERT INTO FUNCTION file('demo_small.csv', 'CSV', 'id UInt32, name String')
VALUES (1, 'alice'), (2, 'bob');

INSERT INTO FUNCTION file('demo_medium.csv', 'CSV', 'id UInt32, value Float32')
SELECT number, number * 0.5 FROM numbers(100);

INSERT INTO FUNCTION file('demo_large.csv', 'CSV', 'id UInt32, payload String')
SELECT number, hex(number) FROM numbers(1000);

-- One JSON file
INSERT INTO FUNCTION file('demo_meta.json', 'JSONEachRow', 'k String, v UInt32')
VALUES ('apples', 10), ('bananas', 20), ('cherries', 30);

-- ============================================
-- 2. Inspect Schema of filesystem()
-- ============================================

SELECT '========== 2. filesystem() Schema ==========';

DESCRIBE filesystem('.');

-- ============================================
-- 3. List All Entries (Metadata Only)
-- ============================================

SELECT '========== 3. All Entries Under user_files ==========';

SELECT
    name,
    type,
    size,
    depth,
    modification_time
FROM filesystem('.')
ORDER BY type, name;

-- ============================================
-- 4. Files Only — With Sizes
-- ============================================

SELECT '========== 4. Regular Files Sorted by Size ==========';

SELECT
    name,
    size AS bytes,
    formatReadableSize(size) AS pretty_size
FROM filesystem('.')
WHERE type = 'regular'
ORDER BY size DESC;

-- ============================================
-- 5. Read File Contents
-- ============================================

SELECT '========== 5. Reading File Contents Inline ==========';

SELECT
    name,
    substring(content, 1, 80) AS first_80_chars
FROM filesystem('.')
WHERE type = 'regular' AND name LIKE 'demo_%'
ORDER BY name;

-- ============================================
-- 6. Filter by File Extension and Permission
-- ============================================

SELECT '========== 6. CSV Files Only (Extension + Type Filter) ==========';

SELECT
    name,
    size,
    owner_read,
    owner_write,
    others_read
FROM filesystem('.')
WHERE type = 'regular'
  AND name LIKE '%.csv'
ORDER BY name;

-- ============================================
-- 7. Aggregations Over the Filesystem
-- ============================================

SELECT '========== 7. Aggregate Stats Per File Type ==========';

SELECT
    type,
    count() AS entry_count,
    sum(size) AS total_bytes,
    formatReadableSize(sum(size)) AS pretty_total
FROM filesystem('.')
GROUP BY type
ORDER BY entry_count DESC;

-- ============================================
-- 8. Files Modified Recently
-- ============================================

SELECT '========== 8. Files Modified Within the Last Hour ==========';

SELECT
    name,
    modification_time,
    dateDiff('second', modification_time, now64()) AS seconds_ago,
    size
FROM filesystem('.')
WHERE type = 'regular'
  AND modification_time > now64() - INTERVAL 1 HOUR
ORDER BY modification_time DESC
LIMIT 10;

-- ============================================
-- 9. Pair filesystem() Discovery With file() Per-File Reads
-- ============================================

SELECT '========== 9. Inventory + Individual file() Reads ==========';

-- filesystem() discovers which files exist
SELECT 'Discovered CSV files:' AS step;

SELECT name, size
FROM filesystem('.')
WHERE type = 'regular' AND name LIKE 'demo_%.csv'
ORDER BY name;

-- file() reads each one; row counts shown individually
SELECT 'Row count: demo_small.csv'  AS step, count() AS rows FROM file('demo_small.csv',  'CSV');
SELECT 'Row count: demo_medium.csv' AS step, count() AS rows FROM file('demo_medium.csv', 'CSV');
SELECT 'Row count: demo_large.csv'  AS step, count() AS rows FROM file('demo_large.csv',  'CSV');

-- ============================================
-- 10. Permission Audit (read-only listing)
-- ============================================

SELECT '========== 10. Permission Audit ==========';

SELECT
    name,
    concat(
        if(owner_read,  'r', '-'),
        if(owner_write, 'w', '-'),
        if(owner_exec,  'x', '-'),
        if(group_read,  'r', '-'),
        if(group_write, 'w', '-'),
        if(group_exec,  'x', '-'),
        if(others_read, 'r', '-'),
        if(others_write,'w', '-'),
        if(others_exec, 'x', '-')
    ) AS unix_perms,
    size
FROM filesystem('.')
WHERE type = 'regular'
ORDER BY name;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- Note: created files persist in user_files; remove manually if desired:
--   docker exec clickhouse-26-5 rm /var/lib/clickhouse/user_files/demo_*

SELECT '========== Test Complete ==========';
SELECT 'filesystem() makes a directory tree queryable as a regular SQL table.' AS summary;
