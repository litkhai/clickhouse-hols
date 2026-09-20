SET allow_experimental_time_series_table = 1;

SELECT '===== 1. Loading synthetic metrics =====';

-- Simulates a tiny fleet: 3 hosts × 2 metrics × 240 samples (2 hours at a
-- 30-second scrape interval) = 6 series, 1,440 samples total.
--
-- The shape mirrors what a real Prometheus remote-write payload looks like
-- once it lands in ClickHouse: one row per *series* (metric name + tag set),
-- with the samples packed into a single time_series column. In production
-- something in front of this (vmagent, the Prometheus remote_write
-- integration, or your own writer) does this packing for you; here we do it
-- by hand with arrayMap() so the shape stays visible.
INSERT INTO metrics (metric_name, tags, time_series)
SELECT
    metric_name,
    map('host', host, 'region', region),
    arrayMap(i -> (
        now() - toIntervalSecond((239 - i) * 30),
        base + 20 * sin(i / 20.) + (rand(i + sipHash64(host)) % 1000) / 100.
    ), range(240))
FROM (
    SELECT 'cpu_usage' AS metric_name, host, region, base
    FROM (SELECT arrayJoin([('web-1', 'apac', 40.), ('web-2', 'apac', 25.), ('db-1', 'us', 65.)]) AS t)
    ARRAY JOIN [t.1] AS host, [t.2] AS region, [t.3] AS base
    UNION ALL
    SELECT 'memory_usage' AS metric_name, host, region, base
    FROM (SELECT arrayJoin([('web-1', 'apac', 55.), ('web-2', 'apac', 48.), ('db-1', 'us', 80.)]) AS t)
    ARRAY JOIN [t.1] AS host, [t.2] AS region, [t.3] AS base
);

SELECT '===== 2. Verifying the load =====';

-- The outer `metrics` table cannot be SELECTed directly (see the gotcha in
-- 05-management.sql), so the real verification that six series with 240
-- samples each landed correctly happens through PromQL, in 03-promql-instant.sql.
-- 05-management.sql also shows how to confirm it via the inner tables directly.
SELECT 'load complete — run 03-promql-instant.sh next' AS next_step;
