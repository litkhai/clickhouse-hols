-- ClickHouse 25.4: toInterval and Database Comments Test
-- New Features: toInterval(value, unit) as the function form of INTERVAL, and
--               ALTER DATABASE ... MODIFY COMMENT
-- Reference: https://clickhouse.com/docs/whats-new/changelog (25.4, #78723, #75622)

-- toInterval is the function form of the INTERVAL keyword. The *value* may be
-- an expression, but the unit must still be a constant string — so this lab
-- also shows what to do when the unit genuinely varies per row.

-- ============================================
-- 1. toInterval Basics
-- ============================================

SELECT '========== 1. toInterval(value, unit) ==========';

SELECT
    toInterval(5, 'day')     AS five_days,
    toInterval(2, 'hour')    AS two_hours,
    toInterval(30, 'minute') AS thirty_minutes;

-- ============================================
-- 2. Arithmetic With It
-- ============================================

SELECT '========== 2. Using It in Date Arithmetic ==========';

SELECT
    toDateTime('2025-04-30 12:00:00')                          AS base,
    toDateTime('2025-04-30 12:00:00') + toInterval(2, 'hour')  AS plus_2h,
    toDateTime('2025-04-30 12:00:00') - toInterval(7, 'day')   AS minus_7d,
    toDateTime('2025-04-30 12:00:00') + toInterval(1, 'month') AS plus_1mo;

-- ============================================
-- 3. Compared With the INTERVAL Keyword
-- ============================================

SELECT '========== 3. Same Result as INTERVAL ==========';

SELECT
    toDateTime('2025-04-30 12:00:00') + INTERVAL 2 HOUR        AS keyword_form,
    toDateTime('2025-04-30 12:00:00') + toInterval(2, 'hour')  AS function_form,
    keyword_form = function_form                                AS identical;

-- ============================================
-- 4. The Value May Be an Expression
-- ============================================

SELECT '========== 4. The Value May Be an Expression ==========';

-- The amount can come from a column...
SELECT number AS days_back, now() - toInterval(number, 'day') AS cutoff
FROM numbers(3);

-- ...but the unit cannot: toInterval(n, unit_column) fails with
-- "Second argument for function toInterval must be constant string".
DROP TABLE IF EXISTS retention_rules;

CREATE TABLE retention_rules
(
    dataset  String,
    keep_for UInt32,
    unit     String
)
ENGINE = MergeTree
ORDER BY dataset;

INSERT INTO retention_rules VALUES
    ('access_logs',   14, 'day'),
    ('audit_trail',    7, 'year'),
    ('debug_traces',  12, 'hour'),
    ('billing_events', 3, 'month');

-- With a per-row unit, branch on the unit and let each branch use its own
-- constant. Branch on the resulting timestamp, not on the interval: intervals
-- of different units have no common type.
SELECT
    dataset,
    keep_for,
    unit,
    multiIf(
        unit = 'hour',  now() - toInterval(keep_for, 'hour'),
        unit = 'day',   now() - toInterval(keep_for, 'day'),
        unit = 'month', now() - toInterval(keep_for, 'month'),
                        now() - toInterval(keep_for, 'year')
    ) AS delete_before
FROM retention_rules
ORDER BY dataset;

-- ============================================
-- 5. A Retention Filter Driven by a Table
-- ============================================

SELECT '========== 5. Applying Per-Dataset Retention ==========';

DROP TABLE IF EXISTS records;

CREATE TABLE records (dataset String, ts DateTime, payload String)
ENGINE = MergeTree ORDER BY (dataset, ts);

INSERT INTO records
SELECT
    ['access_logs', 'audit_trail', 'debug_traces', 'billing_events'][number % 4 + 1],
    now() - toIntervalDay(number % 400),
    concat('row_', toString(number))
FROM numbers(4000);

SELECT
    r.dataset,
    count() AS total_rows,
    countIf(r.ts < multiIf(
        rr.unit = 'hour',  now() - toInterval(rr.keep_for, 'hour'),
        rr.unit = 'day',   now() - toInterval(rr.keep_for, 'day'),
        rr.unit = 'month', now() - toInterval(rr.keep_for, 'month'),
                           now() - toInterval(rr.keep_for, 'year')
    )) AS expired_rows
FROM records AS r
INNER JOIN retention_rules AS rr ON r.dataset = rr.dataset
GROUP BY r.dataset
ORDER BY r.dataset;

-- ============================================
-- 6. Supported Units
-- ============================================

SELECT '========== 6. The Unit Vocabulary ==========';

-- Each call needs its own constant, so the vocabulary is listed explicitly.
SELECT
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'second')  AS plus_second,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'minute')  AS plus_minute,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'hour')    AS plus_hour,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'day')     AS plus_day;

SELECT
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'week')    AS plus_week,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'month')   AS plus_month,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'quarter') AS plus_quarter,
    toDateTime('2025-04-30 00:00:00') + toInterval(1, 'year')    AS plus_year;

-- ============================================
-- 7. Database Comments
-- ============================================

SELECT '========== 7. CREATE DATABASE ... COMMENT ==========';

DROP DATABASE IF EXISTS documented;

CREATE DATABASE documented COMMENT 'Staging area for the ingest pipeline';

SELECT name, comment FROM system.databases WHERE name = 'documented';

-- ============================================
-- 8. Changing the Comment
-- ============================================

SELECT '========== 8. ALTER DATABASE ... MODIFY COMMENT ==========';

-- New in 25.4: the comment is no longer fixed at creation.
ALTER DATABASE documented MODIFY COMMENT 'Owned by the data platform team; retention rules in retention_rules';

SELECT name, comment FROM system.databases WHERE name = 'documented';

-- ============================================
-- 9. Comments as Queryable Metadata
-- ============================================

SELECT '========== 9. Searching the Catalogue ==========';

DROP DATABASE IF EXISTS analytics_marts;
CREATE DATABASE analytics_marts COMMENT 'Owned by the analytics team';

SELECT name, comment
FROM system.databases
WHERE comment != ''
ORDER BY name;

SELECT
    name,
    comment
FROM system.databases
WHERE comment ILIKE '%data platform%'
ORDER BY name;

-- ============================================
-- 10. Clearing a Comment
-- ============================================

SELECT '========== 10. Removing It Again ==========';

ALTER DATABASE analytics_marts MODIFY COMMENT '';

SELECT name, comment = '' AS comment_cleared
FROM system.databases
WHERE name = 'analytics_marts';

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP DATABASE IF EXISTS documented;
-- DROP DATABASE IF EXISTS analytics_marts;
-- DROP TABLE IF EXISTS retention_rules;
-- DROP TABLE IF EXISTS records;

SELECT '========== Test Complete ==========';
SELECT 'toInterval takes an expression for the amount, a constant for the unit.' AS summary;
