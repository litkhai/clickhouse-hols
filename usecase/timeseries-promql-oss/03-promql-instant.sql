SET allow_experimental_time_series_table = 1;
SET allow_experimental_time_series_aggregate_functions = 1;

SELECT '===== Switching the session to PromQL =====';

-- These two settings switch the *entire* client session to PromQL: every
-- query below is PromQL text, not SQL, until the session ends or you
-- `SET dialect = 'clickhouse'` again. Because of that, the section banners
-- from here on are `--` comments rather than `SELECT '...'` — a SQL string
-- literal is not valid PromQL and the query would fail to parse.
SET dialect = 'promql';
SET promql_table = 'metrics';

-- ----- 1. Instant vector: every series for one metric -----
-- Returns one row per series (metric name + tag set), each with the single
-- sample closest to "now". This is the PromQL equivalent of
-- `SELECT DISTINCT ON (tags) ... ORDER BY timestamp DESC`.
cpu_usage;

-- ----- 2. Label matching -----
-- Curly braces filter by tag. `=` is exact match; PromQL also supports
-- `!=`, `=~` (regex match) and `!~` (regex non-match) — try changing this one.
cpu_usage{host="web-1"};

-- ----- 3. Aggregation across the label dimension -----
-- `by (...)` keeps only the listed labels in the result, collapsing
-- everything else — here, three per-host series become two per-region ones.
avg(cpu_usage) by (region);

-- ----- 4. topk -----
-- Not a plain aggregation — this is why allow_experimental_time_series_aggregate_functions
-- had to be set above, separately from allow_experimental_time_series_table.
topk(2, memory_usage);

-- Switch back to SQL for the rest of the labs in this directory.
SET dialect = 'clickhouse';

SELECT '===== Back to SQL =====';
SELECT 'dialect is back to clickhouse — this line is plain SQL again' AS note;
