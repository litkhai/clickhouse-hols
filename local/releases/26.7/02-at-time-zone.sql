-- ClickHouse 26.7: AT TIME ZONE / AT LOCAL Postfix Operators Test
-- New Feature: the standard SQL postfix operators `AT TIME ZONE '<tz>'` and `AT LOCAL`.
-- Reference: https://clickhouse.com/docs/whats-new/changelog (26.7, #106092)

-- These are the ANSI spellings of toTimeZone(). Reports ported from Postgres, Snowflake or
-- BigQuery can keep their original expressions instead of being rewritten.

-- ============================================
-- 1. The Basics
-- ============================================

SELECT '========== 1. AT TIME ZONE ==========';

SELECT
    toDateTime('2026-07-22 12:00:00', 'UTC')                            AS utc,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul'  AS seoul,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Europe/Paris' AS paris,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'America/New_York' AS new_york;

-- The operator changes the time zone attached to the value, not the instant it denotes.
SELECT
    toTypeName(toDateTime('2026-07-22 12:00:00', 'UTC'))                           AS original_type,
    toTypeName(toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul') AS converted_type,
    toUnixTimestamp(toDateTime('2026-07-22 12:00:00', 'UTC'))                      AS utc_epoch,
    toUnixTimestamp(toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul') AS seoul_epoch;

-- ============================================
-- 2. Equivalent to toTimeZone
-- ============================================

SELECT '========== 2. Same Result as toTimeZone ==========';

SELECT
    toTimeZone(toDateTime('2026-07-22 12:00:00', 'UTC'), 'Asia/Seoul')  AS function_form,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul'  AS operator_form,
    toTimeZone(toDateTime('2026-07-22 12:00:00', 'UTC'), 'Asia/Seoul')
        = (toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul') AS identical;

-- ============================================
-- 3. AT LOCAL
-- ============================================

SELECT '========== 3. AT LOCAL Follows the Session Time Zone ==========';

SET session_timezone = 'Asia/Seoul';

SELECT
    'session_timezone = Asia/Seoul'                             AS context,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT LOCAL           AS at_local;

SET session_timezone = 'America/Los_Angeles';

SELECT
    'session_timezone = America/Los_Angeles'                    AS context,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT LOCAL           AS at_local;

SET session_timezone = 'UTC';

-- ============================================
-- 4. Chained Conversions
-- ============================================

SELECT '========== 4. Chaining ==========';

-- Each operator re-labels the same instant, so the last one in the chain wins.
SELECT
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul'                             AS one_hop,
    toDateTime('2026-07-22 12:00:00', 'UTC') AT TIME ZONE 'Asia/Seoul' AT TIME ZONE 'America/New_York' AS two_hops;

-- ============================================
-- 5. Sub-Second Precision Survives
-- ============================================

SELECT '========== 5. DateTime64 ==========';

SELECT
    toDateTime64('2026-07-22 12:00:00.123456', 6, 'UTC')                            AS utc_micros,
    toDateTime64('2026-07-22 12:00:00.123456', 6, 'UTC') AT TIME ZONE 'Asia/Seoul'  AS seoul_micros,
    toTypeName(toDateTime64('2026-07-22 12:00:00.123456', 6, 'UTC') AT TIME ZONE 'Asia/Seoul') AS type;

-- ============================================
-- 6. Per-Row Conversion in a Report
-- ============================================

SELECT '========== 6. Rendering One Event in Every Office Time Zone ==========';

DROP TABLE IF EXISTS deploys;

CREATE TABLE deploys
(
    deploy_id UInt32,
    service   String,
    ts_utc    DateTime('UTC')
)
ENGINE = MergeTree
ORDER BY deploy_id;

INSERT INTO deploys VALUES
    (1, 'api',      '2026-07-22 23:30:00'),
    (2, 'web',      '2026-07-23 07:15:00'),
    (3, 'worker',   '2026-07-23 14:45:00'),
    (4, 'ingest',   '2026-07-23 21:05:00');

SELECT
    deploy_id,
    service,
    ts_utc,
    ts_utc AT TIME ZONE 'Asia/Seoul'      AS seoul,
    ts_utc AT TIME ZONE 'Europe/London'   AS london,
    ts_utc AT TIME ZONE 'America/Chicago' AS chicago
FROM deploys
ORDER BY deploy_id;

-- ============================================
-- 7. The Classic Reporting Bug
-- ============================================

SELECT '========== 7. Local Calendar Day vs UTC Calendar Day ==========';

-- A deploy at 23:30 UTC already belongs to the next day in Seoul. Grouping on the raw UTC
-- value silently attributes it to the wrong local day.
SELECT
    deploy_id,
    ts_utc,
    toDate(ts_utc)                                AS utc_day,
    toDate(ts_utc AT TIME ZONE 'Asia/Seoul')      AS seoul_day,
    toDate(ts_utc) != toDate(ts_utc AT TIME ZONE 'Asia/Seoul') AS day_differs
FROM deploys
ORDER BY deploy_id;

SELECT
    toDate(ts_utc AT TIME ZONE 'Asia/Seoul') AS seoul_day,
    count()                                  AS deploys,
    groupArray(service)                      AS services
FROM deploys
GROUP BY seoul_day
ORDER BY seoul_day;

-- ============================================
-- 8. Filtering Is Unaffected
-- ============================================

SELECT '========== 8. Comparisons Use the Instant, Not the Label ==========';

-- Both predicates select the same rows: the conversion is presentational.
SELECT count() AS via_utc
FROM deploys
WHERE ts_utc >= toDateTime('2026-07-23 00:00:00', 'UTC');

SELECT count() AS via_converted
FROM deploys
WHERE (ts_utc AT TIME ZONE 'Asia/Seoul') >= toDateTime('2026-07-23 00:00:00', 'UTC');

-- To filter on a *local* calendar boundary, convert the boundary too.
SELECT count() AS seoul_day_23
FROM deploys
WHERE toDate(ts_utc AT TIME ZONE 'Asia/Seoul') = toDate('2026-07-23');

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS deploys;

SELECT '========== Test Complete ==========';
SELECT 'AT TIME ZONE / AT LOCAL bring ANSI time zone syntax to ClickHouse.' AS summary;
