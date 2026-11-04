-- ClickHouse 25.6 Feature: CoalescingMergeTree
-- Purpose: show what the engine really does. For each key it keeps, per column,
--          the latest non-NULL value. It has no Sign column and no +1/-1 collapse.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06
-- Nothing here raises an exception, so the file runs to the end in one pass.

DROP TABLE IF EXISTS device_coalescing;
DROP TABLE IF EXISTS device_replacing;
DROP TABLE IF EXISTS device_cols;
DROP TABLE IF EXISTS device_plain;

-- 1. Sparse updates: every insert for device 1 sets one or two columns, the rest are NULL.
SELECT '=== 1. CoalescingMergeTree ORDER BY key, Nullable value columns ===' AS title;

CREATE TABLE device_coalescing
(
    device_id UInt32,
    firmware  Nullable(String),
    temp_c    Nullable(Float64),
    battery   Nullable(UInt8)
)
ENGINE = CoalescingMergeTree
ORDER BY device_id;

-- One INSERT = one part, so the four rows below stay unmerged until OPTIMIZE.
INSERT INTO device_coalescing VALUES (1, 'v1.0', NULL, NULL);
INSERT INTO device_coalescing VALUES (1, NULL, 21.5, NULL);
INSERT INTO device_coalescing VALUES (1, NULL, NULL, 80);
INSERT INTO device_coalescing VALUES (1, 'v1.1', NULL, 75);

SELECT '--- parts before any merge' AS step;
SELECT name, rows FROM system.parts
WHERE database = currentDatabase() AND table = 'device_coalescing' AND active ORDER BY name;

SELECT '--- plain SELECT: the four sparse rows, as long as no background merge has run yet' AS step;
SELECT * FROM device_coalescing ORDER BY firmware, temp_c, battery;

SELECT '--- SELECT ... FINAL: one row, each column = latest non-NULL value' AS step;
SELECT * FROM device_coalescing FINAL;

OPTIMIZE TABLE device_coalescing FINAL;

SELECT '--- after OPTIMIZE FINAL: the merge wrote the same single row to disk' AS step;
SELECT * FROM device_coalescing;
SELECT name, rows FROM system.parts
WHERE database = currentDatabase() AND table = 'device_coalescing' AND active ORDER BY name;

-- 2. Same inserts into ReplacingMergeTree: the whole latest row wins.
SELECT '=== 2. The same inserts into ReplacingMergeTree ===' AS title;

CREATE TABLE device_replacing
(
    device_id UInt32,
    firmware  Nullable(String),
    temp_c    Nullable(Float64),
    battery   Nullable(UInt8)
)
ENGINE = ReplacingMergeTree
ORDER BY device_id;

INSERT INTO device_replacing VALUES (1, 'v1.0', NULL, NULL);
INSERT INTO device_replacing VALUES (1, NULL, 21.5, NULL);
INSERT INTO device_replacing VALUES (1, NULL, NULL, 80);
INSERT INTO device_replacing VALUES (1, 'v1.1', NULL, 75);

SELECT '--- FINAL: the last row replaces the others; temp_c 21.5 is lost (NULL)' AS step;
SELECT * FROM device_replacing FINAL;

-- 3. Side by side.
SELECT '=== 3. Side by side (FINAL) ===' AS title;
SELECT 'CoalescingMergeTree' AS engine, firmware, temp_c, battery FROM device_coalescing FINAL
UNION ALL
SELECT 'ReplacingMergeTree', firmware, temp_c, battery FROM device_replacing FINAL;

-- 4. The engine parameter is a list of columns to coalesce, not a Sign column.
SELECT '=== 4. CoalescingMergeTree(columns): only the listed columns are coalesced ===' AS title;

CREATE TABLE device_cols
(
    device_id UInt32,
    temp_c    Nullable(Float64),
    note      Nullable(String)
)
ENGINE = CoalescingMergeTree(temp_c)
ORDER BY device_id;

INSERT INTO device_cols VALUES (1, 21.5, 'first');
INSERT INTO device_cols VALUES (1, NULL, 'second');
INSERT INTO device_cols VALUES (1, NULL, NULL);
OPTIMIZE TABLE device_cols FINAL;

SELECT '--- temp_c (listed) keeps 21.5 across later NULLs; note (not listed) is not coalesced: it kept the first insert, not the latest or a non-NULL pick' AS step;
SELECT * FROM device_cols;

-- 5. Non-Nullable columns have no NULL to skip.
SELECT '=== 5. Non-Nullable columns: no NULL to skip, so the latest row wins ===' AS title;

CREATE TABLE device_plain
(
    device_id UInt32,
    firmware  String,
    battery   UInt8
)
ENGINE = CoalescingMergeTree
ORDER BY device_id;

INSERT INTO device_plain VALUES (1, 'v1.1', 75);
INSERT INTO device_plain VALUES (1, '', 0);
OPTIMIZE TABLE device_plain FINAL;

SELECT * FROM device_plain;

-- Cleanup (commented out for inspection)
-- DROP TABLE device_coalescing; DROP TABLE device_replacing;
-- DROP TABLE device_cols; DROP TABLE device_plain;

SELECT '✅ CoalescingMergeTree test complete' AS status;
