-- ClickHouse 26.6: ALTER TABLE ... ADD ENUM VALUES Test
-- New Feature: append values to an existing Enum without restating the values it already has.
-- Reference: https://clickhouse.com/blog/clickhouse-release-26-06

-- Before 26.6 every Enum extension meant re-declaring the whole type. Restating a 40-value
-- taxonomy to add one member is error-prone: drop a value by accident and the ALTER either
-- fails or rewrites data. ADD ENUM VALUES makes the append explicit.

-- ============================================
-- 1. A Taxonomy That Will Need To Grow
-- ============================================

SELECT '========== 1. Initial Event Taxonomy ==========';

DROP TABLE IF EXISTS app_events;

CREATE TABLE app_events
(
    event_id   UInt64,
    ts         DateTime,
    event_type Enum8('click' = 1, 'view' = 2, 'purchase' = 3)
)
ENGINE = MergeTree
ORDER BY event_id;

INSERT INTO app_events
SELECT
    number,
    toDateTime('2026-06-25 00:00:00') + number,
    ['click', 'view', 'purchase'][number % 3 + 1]
FROM numbers(200000);

SELECT event_type, count() AS events FROM app_events GROUP BY event_type ORDER BY event_type;

-- ============================================
-- 2. The Pre-26.6 Way (Still Valid)
-- ============================================

SELECT '========== 2. Old Way: Restate Every Value ==========';

-- Adding 'refund' used to require listing click/view/purchase again.
ALTER TABLE app_events
    MODIFY COLUMN event_type Enum8('click' = 1, 'view' = 2, 'purchase' = 3, 'refund' = 4);

SELECT type AS after_full_restatement FROM system.columns
WHERE table = 'app_events' AND name = 'event_type';

-- ============================================
-- 3. The 26.6 Way — Append Only
-- ============================================

SELECT '========== 3. New Way: ADD ENUM VALUES ==========';

-- Only the new member is named. Existing members are untouched by construction.
ALTER TABLE app_events MODIFY COLUMN event_type ADD ENUM VALUES('signup' = 5);

SELECT type AS after_add_enum_values FROM system.columns
WHERE table = 'app_events' AND name = 'event_type';

-- ============================================
-- 4. Letting ClickHouse Assign the Id
-- ============================================

SELECT '========== 4. Auto-Assigned Ids ==========';

-- Omitting '= N' appends at max(id) + 1.
ALTER TABLE app_events MODIFY COLUMN event_type ADD ENUM VALUES('logout');

SELECT type AS auto_assigned FROM system.columns
WHERE table = 'app_events' AND name = 'event_type';

-- ============================================
-- 5. Several Values in One Statement
-- ============================================

SELECT '========== 5. Batch Append ==========';

ALTER TABLE app_events
    MODIFY COLUMN event_type ADD ENUM VALUES('share' = 10, 'bookmark' = 11, 'report' = 12);

SELECT type AS after_batch FROM system.columns
WHERE table = 'app_events' AND name = 'event_type';

-- ============================================
-- 6. Existing Rows Are Untouched
-- ============================================

SELECT '========== 6. Data Preserved, New Values Usable ==========';

-- The 200k original rows still read back unchanged: appending is metadata-only.
SELECT event_type, count() AS events FROM app_events GROUP BY event_type ORDER BY event_type;

INSERT INTO app_events VALUES
    (900001, '2026-06-25 12:00:00', 'signup'),
    (900002, '2026-06-25 12:00:01', 'logout'),
    (900003, '2026-06-25 12:00:02', 'share'),
    (900004, '2026-06-25 12:00:03', 'report');

SELECT event_type, count() AS events
FROM app_events
WHERE event_id >= 900000
GROUP BY event_type
ORDER BY event_type;

-- ============================================
-- 7. Enum16 for Large Taxonomies
-- ============================================

SELECT '========== 7. Enum16 Works the Same Way ==========';

DROP TABLE IF EXISTS error_codes;

CREATE TABLE error_codes
(
    id   UInt64,
    code Enum16('ok' = 0, 'not_found' = 404)
)
ENGINE = MergeTree
ORDER BY id;

ALTER TABLE error_codes MODIFY COLUMN code ADD ENUM VALUES('server_error' = 500, 'timeout' = 504);

SELECT type AS enum16_type FROM system.columns
WHERE table = 'error_codes' AND name = 'code';

-- ============================================
-- 8. Nullable Enums
-- ============================================

SELECT '========== 8. Nullable(Enum8) ==========';

DROP TABLE IF EXISTS optional_stage;

CREATE TABLE optional_stage
(
    id    UInt64,
    stage Nullable(Enum8('new' = 1, 'active' = 2))
)
ENGINE = MergeTree
ORDER BY id;

ALTER TABLE optional_stage MODIFY COLUMN stage ADD ENUM VALUES('archived' = 3);

INSERT INTO optional_stage VALUES (1, 'new'), (2, NULL), (3, 'archived');

SELECT id, stage FROM optional_stage ORDER BY id;

-- ============================================
-- 9. Ordering Follows the Id, Not the Name
-- ============================================

SELECT '========== 9. Enum Ordering Semantics ==========';

-- ORDER BY on an Enum column sorts by the numeric id, so an appended value sorts last
-- regardless of its name. Cast to String when alphabetical order is what you want.
SELECT event_type, toInt16(event_type) AS enum_id
FROM app_events
WHERE event_id >= 900000
ORDER BY event_type;

SELECT toString(event_type) AS name
FROM app_events
WHERE event_id >= 900000
ORDER BY name;

-- ============================================
-- 10. Full Definition
-- ============================================

SELECT '========== 10. Final DDL ==========';

SHOW CREATE TABLE app_events;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS app_events;
-- DROP TABLE IF EXISTS error_codes;
-- DROP TABLE IF EXISTS optional_stage;

SELECT '========== Test Complete ==========';
SELECT 'ADD ENUM VALUES turns a whole-type rewrite into an append.' AS summary;
