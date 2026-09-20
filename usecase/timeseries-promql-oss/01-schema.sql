SELECT '===== 1. Enabling the experimental settings =====';

-- Two separate flags are needed, and the error messages that fire when you
-- forget one are two different exceptions with two different names — easy to
-- fix one and still be stuck on the other:
--   - allow_experimental_time_series_table            → lets you CREATE ... ENGINE = TimeSeries
--                                                          and use the `promql` dialect at all
--   - allow_experimental_time_series_aggregate_functions → lets you call rate()/delta()/increase()/
--                                                          topk()/bottomk() through PromQL
SET allow_experimental_time_series_table = 1;
SET allow_experimental_time_series_aggregate_functions = 1;

SELECT '===== 2. Creating a TimeSeries table =====';

DROP TABLE IF EXISTS metrics;

CREATE TABLE metrics ENGINE = TimeSeries;

SELECT '===== 3. What CREATE TABLE actually built =====';

-- A single `ENGINE = TimeSeries` statement is a facade over four regular
-- MergeTree-family tables. This is worth looking at once, because every
-- design choice below explains something you would otherwise have to guess:
--   - `samples`        MergeTree, ORDER BY (id, timestamp)        — the raw data points
--   - `tags`            AggregatingMergeTree, PRIMARY KEY metric_name — the label sets (one row per series)
--   - `metrics`         ReplacingMergeTree, ORDER BY metric_family_name — metric metadata (type/unit/help)
--   - `recent_samples`  MergeTree with a TTL                       — a short-lived hot copy for fast recent-data reads
--
-- The outer `metrics` table itself has no queryable rows of its own — see
-- the gotcha in 05-management.sql about why `SELECT * FROM metrics` fails.
SHOW CREATE TABLE metrics FORMAT Vertical;

SELECT '===== 4. The outer (logical) columns you INSERT into =====';

-- Despite the four inner tables above, INSERT targets a much simpler logical
-- shape: one row per *series* (a metric name + a specific set of tags), with
-- all of that series' data points packed into a single Array(Tuple) column.
DESCRIBE TABLE metrics;
