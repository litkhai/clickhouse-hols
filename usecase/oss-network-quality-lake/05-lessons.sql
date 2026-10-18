-- Lessons from the field, checked on the lab's own data.

-- ---------------------------------------------------------------- gold builds on gold
-- The 10-minute rollup (fed by the 1-minute one) must equal a 10-minute aggregate computed
-- straight from silver, for every complete 10-minute bucket.
CREATE OR REPLACE VIEW oss_lake.lesson_10m_from_gold AS
SELECT bucket, cell, uniqMerge(users_st) AS users, sum(samples_n) AS samples,
       sum(rsrp_n) AS rsrp_n, sum(rsrp_sum) AS rsrp_sum, sum(poor_n) AS poor_n
FROM oss_lake.cell_kpi_10m
WHERE bucket < toStartOfTenMinutes((SELECT max(anchor_ts) FROM oss_lake.params))
GROUP BY bucket, cell;

CREATE OR REPLACE VIEW oss_lake.lesson_10m_from_silver AS
SELECT toStartOfTenMinutes(event_ts) AS bucket, h3 AS cell, uniq(imsi_hash) AS users,
       count() AS samples, count(rsrp) AS rsrp_n, sum(ifNull(rsrp, 0)) AS rsrp_sum,
       countIf(rsrp < -100) AS poor_n
FROM oss_lake.ue_trace
WHERE event_ts < toDateTime64(toStartOfTenMinutes((SELECT max(anchor_ts) FROM oss_lake.params)), 3)
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

-- Bronze keeps every row it was sent: 180,000 per generated minute.
SELECT throwIf((SELECT count() FROM oss_lake.ue_trace_raw)
               != 180000 * (SELECT uniqExact(toStartOfMinute(event_ts)) FROM oss_lake.ue_trace_raw),
               'bronze lost or duplicated rows') FORMAT Null;

-- Gold along geography: every silver row of the hour lands in exactly one district.
SELECT throwIf((SELECT sum(samples_n) FROM oss_lake.region_kpi_1m) != (SELECT count() FROM oss_lake.ue_trace),
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
