-- 02-load.sql: 36,000,000 synthetic page views over three hours (2026-11-01 00:00 to 02:59 UTC),
-- 200,000 per minute, in 12 INSERTs of 15 minutes each. A 15-minute batch splits some 10-minute
-- buckets across two INSERTs, as uneven batches do in practice; the rollups merge the partial states.
--
-- Generator (deterministic, no rand()):
--   user u    = cityHash64(number, 2) % 500000         500,000 users, uniform per event
--   page      = floor(2000 * x^2.5), x from cityHash64(u, 3)
--               fixed per user; 2,000 pages, a few hold most users (page 0 about 5%)
--   kind      = view 60%, click 20%, scroll 10%, purchase 10%
--   user_u32 = u, user_u64 = sipHash64(u), user_str = hex(MD5(toString(u))): the same user three ways

-- batch 1 of 12: 00:00 to 00:14
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(0, 3000000);

-- batch 2 of 12: 00:15 to 00:29
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(3000000, 3000000);

-- batch 3 of 12: 00:30 to 00:44
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(6000000, 3000000);

-- batch 4 of 12: 00:45 to 00:59
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(9000000, 3000000);

-- batch 5 of 12: 01:00 to 01:14
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(12000000, 3000000);

-- batch 6 of 12: 01:15 to 01:29
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(15000000, 3000000);

-- batch 7 of 12: 01:30 to 01:44
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(18000000, 3000000);

-- batch 8 of 12: 01:45 to 01:59
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(21000000, 3000000);

-- batch 9 of 12: 02:00 to 02:14
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(24000000, 3000000);

-- batch 10 of 12: 02:15 to 02:29
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(27000000, 3000000);

-- batch 11 of 12: 02:30 to 02:44
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(30000000, 3000000);

-- batch 12 of 12: 02:45 to 02:59
INSERT INTO mv_uniq.events
WITH cityHash64(number, 2) % 500000 AS u
SELECT
    toDateTime('2026-11-01 00:00:00', 'UTC') + intDiv(number, 200000) * 60 + cityHash64(number, 1) % 60 AS ts,
    ['view', 'view', 'view', 'view', 'view', 'view', 'click', 'click', 'scroll', 'purchase'][1 + cityHash64(number, 4) % 10] AS kind,
    toUInt32(floor(2000 * pow((cityHash64(u, 3) % 1000000) / 1000000., 2.5))) AS page,
    toUInt32(u)           AS user_u32,
    sipHash64(u)          AS user_u64,
    hex(MD5(toString(u))) AS user_str,
    toFloat32(20 + (cityHash64(number, 5) % 2000) / 10) AS latency_ms
FROM numbers(33000000, 3000000);

-- One part per table, so the sizes below are of fully merged states and no merge runs during the timings.
OPTIMIZE TABLE mv_uniq.events FINAL;
OPTIMIZE TABLE mv_uniq.rollup_1m FINAL;
OPTIMIZE TABLE mv_uniq.rollup_10m FINAL;

SELECT table, count() AS active_parts, sum(rows) AS rows, any(part_type) AS part_type
FROM system.parts
WHERE database = 'mv_uniq' AND active
GROUP BY table
ORDER BY table;
