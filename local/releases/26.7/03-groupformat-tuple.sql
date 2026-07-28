-- ClickHouse 26.7: groupFormat Aggregate + -Tuple Combinator Test
-- New Features:
--   groupFormat('<format>')(cols...) — serialize the rows of each group with any
--     ClickHouse output format, as a single value. (#93201)
--   -Tuple combinator — apply an aggregate element-wise to a Tuple argument. (#98190)
-- Reference: https://clickhouse.com/docs/whats-new/changelog (26.7)

-- ============================================
-- 1. Test Data
-- ============================================

SELECT '========== 1. Test Data ==========';

DROP TABLE IF EXISTS readings;

CREATE TABLE readings
(
    reading_id UInt64,
    device     LowCardinality(String),
    room       LowCardinality(String),
    ts         DateTime,
    temp_c     Decimal(5, 2),
    humidity   Decimal(5, 2)
)
ENGINE = MergeTree
ORDER BY (device, reading_id);

INSERT INTO readings
SELECT
    number,
    ['sensor-a', 'sensor-b', 'sensor-c'][number % 3 + 1],
    ['kitchen', 'lab', 'server-room'][number % 3 + 1],
    toDateTime('2026-07-22 08:00:00') + number * 60,
    18 + (number % 15) + 0.25,
    40 + (number % 30) + 0.5
FROM numbers(90);

SELECT count() AS rows, uniqExact(device) AS devices FROM readings;

-- ============================================
-- 2. groupFormat Basics
-- ============================================

SELECT '========== 2. groupFormat With CSV ==========';

-- The format name is a *parameter* of the aggregate; the columns to serialize are the
-- arguments. The result is one string holding every row of the group.
SELECT groupFormat('CSV')(device, temp_c) AS csv_payload
FROM readings
WHERE reading_id < 5;

-- ============================================
-- 3. Any Output Format Works
-- ============================================

SELECT '========== 3. TSV / JSONEachRow / Values ==========';

SELECT groupFormat('TSV')(device, temp_c) AS tsv
FROM readings
WHERE reading_id < 3;

SELECT groupFormat('JSONEachRow')(device, temp_c) AS json_lines
FROM readings
WHERE reading_id < 3;

SELECT groupFormat('Values')(device, temp_c) AS values_list
FROM readings
WHERE reading_id < 3;

-- ============================================
-- 4. One Payload Per Group
-- ============================================

SELECT '========== 4. Per-Device Payloads ==========';

-- With GROUP BY, each group is serialized independently — a natural fit for building
-- per-tenant or per-device export payloads in a single query.
SELECT
    device,
    count()                                                AS readings,
    groupFormat('CSV')(ts, temp_c, humidity)               AS csv_export
FROM readings
WHERE reading_id < 12
GROUP BY device
ORDER BY device;

-- ============================================
-- 5. JSON Payload for a Webhook
-- ============================================

SELECT '========== 5. JSONEachRow Payload Per Room ==========';

SELECT
    room,
    groupFormat('JSONEachRow')(device, temp_c) AS body
FROM readings
WHERE reading_id < 9
GROUP BY room
ORDER BY room;

-- Gotcha: the arguments are always labelled c1, c2, ... — aliases and even CSVWithNames
-- do not change that. Wrapping them in a *named tuple* is how real keys get into the
-- payload; the tuple members keep their names.
SELECT
    room,
    groupFormat('JSONEachRow')(
        (device, temp_c)::Tuple(sensor String, celsius Decimal(5, 2))
    ) AS body
FROM readings
WHERE reading_id < 6
GROUP BY room
ORDER BY room;

-- ============================================
-- 6. The -Tuple Combinator
-- ============================================

SELECT '========== 6. Element-Wise Aggregation Over Tuples ==========';

-- Instead of repeating the aggregate once per member, apply it to the whole tuple.
SELECT
    sumTuple((temp_c, humidity)) AS sum_pair,
    avgTuple((temp_c, humidity)) AS avg_pair,
    minTuple((temp_c, humidity)) AS min_pair,
    maxTuple((temp_c, humidity)) AS max_pair
FROM readings;

-- The long-hand equivalent, for comparison.
SELECT
    (sum(temp_c), sum(humidity)) AS sum_pair,
    (avg(temp_c), avg(humidity)) AS avg_pair
FROM readings;

-- ============================================
-- 7. Named Tuples Keep Their Names
-- ============================================

SELECT '========== 7. Named Tuple Members ==========';

SELECT
    device,
    sumTuple(m) AS totals,
    avgTuple(m) AS averages
FROM
(
    SELECT device, (temp_c, humidity)::Tuple(temp Decimal(12, 2), hum Decimal(12, 2)) AS m
    FROM readings
)
GROUP BY device
ORDER BY device;

-- Members remain addressable by name.
SELECT
    device,
    sumTuple(m).temp AS total_temp,
    sumTuple(m).hum  AS total_hum
FROM
(
    SELECT device, (temp_c, humidity)::Tuple(temp Decimal(12, 2), hum Decimal(12, 2)) AS m
    FROM readings
)
GROUP BY device
ORDER BY device;

-- ============================================
-- 8. Stacking Combinators
-- ============================================

SELECT '========== 8. -Tuple Combined With -If ==========';

-- Combinators compose: aggregate element-wise, but only over matching rows.
SELECT
    room,
    sumTupleIf((temp_c, humidity), temp_c > 25) AS warm_totals,
    countIf(temp_c > 25)                        AS warm_rows
FROM readings
GROUP BY room
ORDER BY room;

-- ============================================
-- 9. Both Features in One Report
-- ============================================

SELECT '========== 9. Combined Report ==========';

SELECT
    room,
    count()                                     AS readings,
    avgTuple((temp_c, humidity))                AS avg_temp_humidity,
    maxTuple((temp_c, humidity))                AS max_temp_humidity,
    groupFormat('CSV')(device, temp_c)          AS sample_csv
FROM readings
WHERE reading_id < 15
GROUP BY room
ORDER BY room;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS readings;

SELECT '========== Test Complete ==========';
SELECT 'groupFormat serializes a group; -Tuple aggregates a tuple element-wise.' AS summary;
