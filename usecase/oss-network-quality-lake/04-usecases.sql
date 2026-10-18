-- What the lake is used for, beyond the NOC map. Each is a view over gold (one row per
-- minute x cell), so it reads ~1/9 of the raw rows and any window can be re-aggregated.
-- 'Now' is max(params.anchor_ts), as in 03; production would use now().

-- ---------------------------------------------------------------- 1 · ad-hoc analysis
-- A quality analyst's question: where is weak signal concentrated, downtown or at the edge?
CREATE OR REPLACE VIEW oss_lake.uc_analysis AS
WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t
SELECT
    g.city                                                   AS city,
    multiIf(g.ring <= 10, 'downtown', g.ring <= 30, 'middle', 'edge') AS zone,
    uniqExact(k.cell)                                        AS cells,
    sum(k.samples_n)                                         AS samples,
    round(sum(k.rsrp_sum) / sum(k.rsrp_n), 1)                AS avg_rsrp,
    round(100 * sum(k.poor_n) / sum(k.rsrp_n), 1)            AS poor_pct
FROM oss_lake.cell_kpi_1m AS k
INNER JOIN oss_lake.grid AS g ON g.h3 = k.cell
WHERE k.bucket >= t - INTERVAL 1 HOUR AND k.bucket < t
GROUP BY city, zone
ORDER BY city, indexOf(['downtown', 'middle', 'edge'], zone);

-- ---------------------------------------------------------------- 2 · dashboard
-- One point per city per minute for a time-series panel (Grafana, Superset, ...):
-- distinct users (uniq states merged across the city's cells) and weak-signal share.
CREATE OR REPLACE VIEW oss_lake.uc_dashboard AS
WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t
SELECT
    k.bucket                                                 AS minute,
    g.city                                                   AS city,
    uniqMerge(k.users_st)                                    AS users,
    sum(k.samples_n)                                         AS samples,
    round(100 * sum(k.poor_n) / sum(k.rsrp_n), 2)            AS poor_pct
FROM oss_lake.cell_kpi_1m AS k
INNER JOIN oss_lake.grid AS g ON g.h3 = k.cell
WHERE k.bucket >= t - INTERVAL 1 HOUR AND k.bucket < t
GROUP BY minute, city
ORDER BY minute, city;

-- ---------------------------------------------------------------- 3 · alerts
-- Grid cells whose signal in the latest minute is at least 12 dB below their own previous
-- 59 minutes (the minute being judged is not part of its own baseline). In this lab the
-- generator injects one such drop per minute so the pipeline has something to carry; real
-- rules also watch measurement counts collapsing, persistence over several minutes and
-- recent configuration changes.
-- Subscribers (an on-call app, a chat bot) pick these up every minute; see 4 and
-- subscribe-kafka.sql for how they are delivered.
CREATE OR REPLACE VIEW oss_lake.uc_alert_cells AS
WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t
SELECT
    cell, city, area, minute, rsrp_now, rsrp_hour,
    round(rsrp_hour - rsrp_now, 1)                           AS drop_db,
    samples_now
FROM
(
    SELECT
        k.cell                                               AS cell,
        any(g.city)                                          AS city,
        h3ToParent(k.cell, 7)                                AS area,
        t - INTERVAL 1 MINUTE                                AS minute,
        sumIf(k.rsrp_sum, k.bucket = minute) / sumIf(k.rsrp_n, k.bucket = minute) AS rsrp_now,
        sumIf(k.rsrp_sum, k.bucket < minute) / sumIf(k.rsrp_n, k.bucket < minute) AS rsrp_hour,
        sumIf(k.rsrp_n, k.bucket = minute)                   AS samples_now
    FROM oss_lake.cell_kpi_1m AS k
    INNER JOIN oss_lake.grid AS g ON g.h3 = k.cell
    WHERE k.bucket >= t - INTERVAL 1 HOUR AND k.bucket < t
    GROUP BY cell
)
WHERE samples_now >= 3 AND rsrp_hour - rsrp_now >= 12;

-- The same alerts folded per area: what a person is told ("area X, 41 cells, -21 dB").
CREATE OR REPLACE VIEW oss_lake.uc_alert_areas AS
SELECT
    h3ToString(area)                                         AS area,
    any(city)                                                AS city,
    any(dictGet('oss_lake.cell_dict', 'region2', cell))      AS district,
    any(minute)                                              AS minute,
    count()                                                  AS cells,
    round(avg(drop_db), 1)                                   AS drop_db,
    round(avg(rsrp_now), 1)                                  AS rsrp_now
FROM oss_lake.uc_alert_cells
GROUP BY area
ORDER BY cells DESC, area;

-- Checks: the analysis covers 3 cities x 3 zones, the dashboard 3 cities x 60 minutes, and
-- the alert finds the area the generator degraded in the latest minute.
SELECT throwIf(count() != 9, 'analysis is not 3 cities x 3 zones') FROM oss_lake.uc_analysis FORMAT Null;
SELECT throwIf(count() != 180, 'dashboard is not 3 cities x 60 minutes') FROM oss_lake.uc_dashboard FORMAT Null;
SELECT throwIf(count() = 0, 'no alert in the latest minute') FROM oss_lake.uc_alert_areas FORMAT Null;

SELECT * FROM oss_lake.uc_analysis FORMAT PrettyCompactMonoBlock;
SELECT * FROM oss_lake.uc_alert_areas LIMIT 5 FORMAT PrettyCompactMonoBlock;
