SET allow_experimental_time_series_table = 1;
SET allow_experimental_time_series_aggregate_functions = 1;

SELECT '===== PromQL range functions and operators =====';

SET dialect = 'promql';
SET promql_table = 'metrics';

-- ----- 1. rate() over a wider window -----
-- `rate()` needs at least two samples inside the `[...]` range vector to
-- compute anything; a window narrower than your scrape interval (or than the
-- time since your last write) silently returns nothing rather than erroring
-- — worth remembering when a rate() query looks "empty" for no obvious reason.
rate(cpu_usage[10m]);

-- ----- 2. Filtering with a comparison operator -----
-- Binary operators between a vector and a scalar act as a filter: only
-- series whose current value satisfies the comparison are kept.
cpu_usage > 30;

-- ----- 3. Arithmetic on a vector -----
-- Vector-scalar arithmetic transforms every series' value; useful for unit
-- conversion (bytes → MiB, seconds → ms) without leaving PromQL.
cpu_usage * 2;

SET dialect = 'clickhouse';

SELECT '===== Range queries: the shape a dashboard actually renders =====';

-- Instant queries answer "what is the value right now". A dashboard graph
-- needs a *series of points over an interval* — that is what
-- prometheusQueryRange() returns: one row per label set, with time_series
-- holding every (timestamp, value) sample on a fixed step grid. This is a
-- table function (plain SQL), not PromQL text, which is why the dialect is
-- back to 'clickhouse' here — it takes a PromQL *selector string* as an
-- argument rather than being PromQL itself.
SELECT tags, time_series
FROM prometheusQueryRange(metrics, 'cpu_usage{host="web-1"}', now() - INTERVAL 10 MINUTE, now(), 60)
SETTINGS allow_experimental_time_series_aggregate_functions = 1
FORMAT PrettyCompact;
