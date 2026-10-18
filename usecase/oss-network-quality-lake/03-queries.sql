-- The NOC question, asked of every layer:
--   for the last hour, the 10 grid cells with most users and the 10 with the weakest signal
--   (average rsrp, at least 30 rsrp samples, known coverage gaps left out).
-- Each layer answers it with less work; all four must return the same 20 rows.
-- 'The last hour' ends at max(params.anchor_ts); production would use now().
--
-- Bronze and silver compare their DateTime64(3) event_ts with a DateTime64(3) bound on
-- purpose. Measured 2026-10-18 on 26.6.8.7, 26.8.22.13 and 26.9.13.15 (not 25.8.33.6):
-- `event_ts < <DateTime>` is turned into the key condition `event_ts <= <DateTime> - 1 s`,
-- so a granule that starts inside the last second is skipped and its rows silently
-- disappear from the result (README, "A wrong result met on the way").

-- 1 · bronze: parse, de-identify and filter at query time, over every raw row.
CREATE OR REPLACE VIEW oss_lake.noc_from_bronze AS
WITH toDateTime64((SELECT max(anchor_ts) FROM oss_lake.params), 3) AS t
SELECT lr.1 AS list, toUInt8(lr.2) AS rnk, cell, users, samples, avg_rsrp, poor_pct
FROM
(
    SELECT
        stringToH3(assumeNotNull(h3_res09))            AS cell,
        uniq(cityHash64(assumeNotNull(imsi)))          AS users,
        count()                                        AS samples,
        round(avg(rsrp), 1)                            AS avg_rsrp,
        round(100 * countIf(rsrp < -100) / count(rsrp), 1) AS poor_pct,
        count(rsrp) >= 30 AND dictGet('oss_lake.cell_dict', 'known_weak', cell) = 0 AS eligible,
        row_number() OVER (ORDER BY users DESC, cell)  AS r_users,
        row_number() OVER (PARTITION BY eligible ORDER BY avg(rsrp), cell) AS r_signal
    FROM oss_lake.ue_trace_raw
    WHERE event_ts >= t - INTERVAL 1 HOUR AND event_ts < t
      AND h3_res09 IS NOT NULL AND imsi IS NOT NULL
    GROUP BY cell
)
ARRAY JOIN [('users', r_users), ('signal', if(eligible, r_signal, 999))] AS lr
WHERE lr.2 <= 10;

-- 2 · silver: already typed and hashed; still one row per measurement.
CREATE OR REPLACE VIEW oss_lake.noc_from_silver AS
WITH toDateTime64((SELECT max(anchor_ts) FROM oss_lake.params), 3) AS t
SELECT lr.1 AS list, toUInt8(lr.2) AS rnk, cell, users, samples, avg_rsrp, poor_pct
FROM
(
    SELECT
        h3                                             AS cell,
        uniq(imsi_hash)                                AS users,
        count()                                        AS samples,
        round(avg(rsrp), 1)                            AS avg_rsrp,
        round(100 * countIf(rsrp < -100) / count(rsrp), 1) AS poor_pct,
        count(rsrp) >= 30 AND dictGet('oss_lake.cell_dict', 'known_weak', cell) = 0 AS eligible,
        row_number() OVER (ORDER BY users DESC, cell)  AS r_users,
        row_number() OVER (PARTITION BY eligible ORDER BY avg(rsrp), cell) AS r_signal
    FROM oss_lake.ue_trace
    WHERE event_ts >= t - INTERVAL 1 HOUR AND event_ts < t
    GROUP BY cell
)
ARRAY JOIN [('users', r_users), ('signal', if(eligible, r_signal, 999))] AS lr
WHERE lr.2 <= 10;

-- 3 · gold: 60 pre-folded rows per cell instead of every measurement.
CREATE OR REPLACE VIEW oss_lake.noc_from_gold AS
WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t
SELECT lr.1 AS list, toUInt8(lr.2) AS rnk, cell, users, samples, avg_rsrp, poor_pct
FROM
(
    SELECT
        cell,
        uniqMerge(users_st)                            AS users,
        sum(samples_n)                                 AS samples,
        round(sum(rsrp_sum) / sum(rsrp_n), 1)          AS avg_rsrp,
        round(100 * sum(poor_n) / sum(rsrp_n), 1)      AS poor_pct,
        sum(rsrp_n) >= 30 AND dictGet('oss_lake.cell_dict', 'known_weak', cell) = 0 AS eligible,
        row_number() OVER (ORDER BY users DESC, cell)  AS r_users,
        row_number() OVER (PARTITION BY eligible ORDER BY sum(rsrp_sum) / sum(rsrp_n), cell) AS r_signal
    FROM oss_lake.cell_kpi_1m
    WHERE bucket >= t - INTERVAL 1 HOUR AND bucket < t
    GROUP BY cell
)
ARRAY JOIN [('users', r_users), ('signal', if(eligible, r_signal, 999))] AS lr
WHERE lr.2 <= 10;

-- 4 · serving: the answer is already there; refreshed every minute by cell_rank_rmv.
CREATE OR REPLACE VIEW oss_lake.noc_from_serving AS
SELECT list, rnk, cell, users, samples, avg_rsrp, poor_pct
FROM oss_lake.cell_rank_now;

-- Refresh now instead of waiting for the next minute, and wait until it has finished.
SYSTEM REFRESH VIEW oss_lake.cell_rank_rmv;
SYSTEM WAIT VIEW oss_lake.cell_rank_rmv;

SELECT list, rnk, h3ToString(cell) AS cell, users, samples, avg_rsrp, poor_pct
FROM oss_lake.noc_from_serving
ORDER BY list DESC, rnk
FORMAT PrettyCompactMonoBlock;

-- The check. Freeze what serving holds now (the scheduled refresh may swap it while the
-- checks run), then every layer must return exactly those 20 rows, in both directions.
DROP TABLE IF EXISTS oss_lake.check_serving;
CREATE TABLE oss_lake.check_serving ENGINE = Memory AS SELECT * FROM oss_lake.noc_from_serving;
SELECT throwIf(count() != 20, 'serving does not hold 20 rows') FROM oss_lake.check_serving FORMAT Null;

SELECT throwIf(count() != 20, 'bronze did not return 20 rows') FROM oss_lake.noc_from_bronze FORMAT Null;
SELECT throwIf(count() != 0, 'bronze differs from serving')
FROM (SELECT * FROM oss_lake.noc_from_bronze EXCEPT SELECT * FROM oss_lake.check_serving) FORMAT Null;

SELECT throwIf(count() != 20, 'silver did not return 20 rows') FROM oss_lake.noc_from_silver FORMAT Null;
SELECT throwIf(count() != 0, 'silver differs from serving')
FROM (SELECT * FROM oss_lake.noc_from_silver EXCEPT SELECT * FROM oss_lake.check_serving) FORMAT Null;

SELECT throwIf(count() != 20, 'gold did not return 20 rows') FROM oss_lake.noc_from_gold FORMAT Null;
SELECT throwIf(count() != 0, 'gold differs from serving')
FROM (SELECT * FROM oss_lake.noc_from_gold EXCEPT SELECT * FROM oss_lake.check_serving) FORMAT Null;

DROP TABLE oss_lake.check_serving;
SELECT 'OK: bronze, silver, gold and serving return the same 20 rows' AS check;
