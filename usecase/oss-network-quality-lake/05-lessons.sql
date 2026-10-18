-- Lessons from the field, checked on the lab's own data.

-- ---------------------------------------------------------------- gold builds on gold
-- Every check looks at the last complete hour before the lake's 'now' (max(params.anchor_ts)),
-- not at whole tables: on Cloud the layers keep different TTLs (silver 3 days, gold 7 days,
-- row-level, so boundary minutes are cut), and whole-table comparisons would fail days later.
-- They assume an unbroken last hour, as after 02 or a running feed; right after `feed start`
-- skipped a gap, wait an hour before rerunning them.

-- The 10-minute rollup (fed by the 1-minute one) must equal a 10-minute aggregate computed
-- straight from silver, for every complete 10-minute bucket of that hour.
CREATE OR REPLACE VIEW oss_lake.lesson_10m_from_gold AS
WITH toStartOfTenMinutes((SELECT max(anchor_ts) FROM oss_lake.params)) AS t10
SELECT bucket, cell, uniqMerge(users_st) AS users, sum(samples_n) AS samples,
       sum(rsrp_n) AS rsrp_n, sum(rsrp_sum) AS rsrp_sum, sum(poor_n) AS poor_n
FROM oss_lake.cell_kpi_10m
WHERE bucket >= t10 - INTERVAL 1 HOUR AND bucket < t10
GROUP BY bucket, cell;

CREATE OR REPLACE VIEW oss_lake.lesson_10m_from_silver AS
WITH toDateTime64(toStartOfTenMinutes((SELECT max(anchor_ts) FROM oss_lake.params)), 3) AS t10
SELECT toStartOfTenMinutes(event_ts) AS bucket, h3 AS cell, uniq(imsi_hash) AS users,
       count() AS samples, count(rsrp) AS rsrp_n, sum(ifNull(rsrp, 0)) AS rsrp_sum,
       countIf(rsrp < -100) AS poor_n
FROM oss_lake.ue_trace
WHERE event_ts >= t10 - INTERVAL 1 HOUR AND event_ts < t10
GROUP BY bucket, cell;

SELECT throwIf((SELECT count() FROM oss_lake.lesson_10m_from_gold) = 0, 'no 10-minute rows') FORMAT Null;
SELECT throwIf((SELECT count() FROM oss_lake.lesson_10m_from_gold) != (SELECT count() FROM oss_lake.lesson_10m_from_silver),
               '10-minute rollup and silver differ in groups') FORMAT Null;
SELECT throwIf(count() != 0, '10-minute rollup differs from silver')
FROM (SELECT * FROM oss_lake.lesson_10m_from_gold EXCEPT SELECT * FROM oss_lake.lesson_10m_from_silver) FORMAT Null;
-- control: the same comparison with one deliberate difference must find rows
SELECT throwIf(count() = 0, 'control did not fire')
FROM (SELECT bucket, cell, users, samples + 1, rsrp_n, rsrp_sum, poor_n FROM oss_lake.lesson_10m_from_gold
      EXCEPT SELECT * FROM oss_lake.lesson_10m_from_silver) FORMAT Null;

-- Bronze keeps every row it was sent: each of the hour's 60 minutes is there, with exactly 180,000
-- rows (a whole missing minute fails as well as a partial or duplicated one).
CREATE OR REPLACE VIEW oss_lake.lesson_bronze_minutes AS
WITH toDateTime64((SELECT max(anchor_ts) FROM oss_lake.params), 3) AS t
SELECT toStartOfMinute(event_ts) AS minute, count() AS n
FROM oss_lake.ue_trace_raw
WHERE event_ts >= t - INTERVAL 1 HOUR AND event_ts < t
GROUP BY minute;

SELECT throwIf((SELECT count() FROM oss_lake.lesson_bronze_minutes) != 60, 'bronze is missing a minute') FORMAT Null;
SELECT throwIf((SELECT countIf(n != 180000) FROM oss_lake.lesson_bronze_minutes) != 0,
               'bronze lost or duplicated rows') FORMAT Null;

-- Gold along geography: every silver row of the hour lands in exactly one district.
SELECT throwIf(
    (SELECT sum(samples_n) FROM oss_lake.region_kpi_1m
     WHERE bucket >= (SELECT max(anchor_ts) FROM oss_lake.params) - INTERVAL 1 HOUR
       AND bucket <  (SELECT max(anchor_ts) FROM oss_lake.params))
    != (SELECT count() FROM oss_lake.ue_trace
        WHERE event_ts >= toDateTime64((SELECT max(anchor_ts) FROM oss_lake.params), 3) - INTERVAL 1 HOUR
          AND event_ts <  toDateTime64((SELECT max(anchor_ts) FROM oss_lake.params), 3)),
    'region rollup does not add up to silver') FORMAT Null;
SELECT throwIf((SELECT countIf(region2 = '') FROM oss_lake.region_kpi_1m) != 0, 'a row without a district') FORMAT Null;

-- ---------------------------------------------------------------- what a uniq state weighs
-- Serialized size of one state, by input type and by distinct values per group.
CREATE OR REPLACE VIEW oss_lake.lesson_state_size AS
SELECT 'uniq'              AS fn, 'UInt64' AS input, 300  AS distinct_values, length(CAST(uniqState(number) AS String)) AS bytes FROM numbers(300)
UNION ALL SELECT 'uniq', 'String', 300, length(CAST(uniqState(toString(number)) AS String)) FROM numbers(300)
UNION ALL SELECT 'uniqCombined(12)', 'UInt64', 300, length(CAST(uniqCombinedState(12)(number) AS String)) FROM numbers(300)
UNION ALL SELECT 'uniq', 'UInt64', 1000, length(CAST(uniqState(number) AS String)) FROM numbers(1000)
UNION ALL SELECT 'uniqCombined(12)', 'UInt64', 1000, length(CAST(uniqCombinedState(12)(number) AS String)) FROM numbers(1000);

-- The lab's own rollups: average state size per row at each grain.
CREATE OR REPLACE VIEW oss_lake.lesson_grain AS
SELECT '1 minute' AS grain, count() AS rows, round(avg(length(CAST(users_st AS String)))) AS avg_state_bytes,
       sum(length(CAST(users_st AS String))) AS total_state_bytes
FROM oss_lake.cell_kpi_1m FINAL
UNION ALL
SELECT '10 minutes', count(), round(avg(length(CAST(users_st AS String)))), sum(length(CAST(users_st AS String)))
FROM oss_lake.cell_kpi_10m FINAL;

SELECT * FROM oss_lake.lesson_state_size FORMAT PrettyCompactMonoBlock;
SELECT * FROM oss_lake.lesson_grain FORMAT PrettyCompactMonoBlock;
SELECT 'OK: 10-minute rollup equals silver; region rollup adds up' AS check;
