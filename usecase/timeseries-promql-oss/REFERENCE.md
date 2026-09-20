# TimeSeries + PromQL — Reference

A standalone reference for ClickHouse's `TimeSeries` table engine and PromQL
dialect, distilled from hands-on verification against **ClickHouse OSS
26.8.8**. For the guided, runnable version of this material see the numbered
`.sql`/`.sh` files and [`README.md`](./README.md) in this directory.

## 1. What this is

- **`TimeSeries` table engine** — a native way to store Prometheus-shaped
  data (metric name, tag set, timestamped samples) in ClickHouse.
- **PromQL dialect** — a second SQL parser mode (`SET dialect = 'promql'`)
  that lets you query a `TimeSeries` table with actual PromQL instead of SQL.

Both are still marked experimental. Treat every detail below as tied to
26.8.8, not a stable contract — re-verify against your own target version.

## 2. Version timeline

| Version | What landed | Source |
|---|---|---|
| 24.8 LTS (2024-08-30) | `TimeSeries` engine introduced, behind `allow_experimental_time_series_table` | [PR #64183](https://github.com/ClickHouse/ClickHouse/pull/64183), merged 2024-08-08 |
| 25.6 (2025-06-26) | `timeSeries*ToGrid` SQL-native helper/aggregate functions — a later, separate addition, not the engine | [PR #80590](https://github.com/ClickHouse/ClickHouse/pull/80590), merged 2025-06-05 |
| 25.8 (2025-08-28) | PromQL dialect, `rate`/`delta`/`increase` | [PR #75036](https://github.com/ClickHouse/ClickHouse/pull/75036), merged 2025-08-23 |
| 25.9 → 26.8 | More PromQL functions/operators, `topk`/`bottomk`. SQL `SELECT` on a `TimeSeries` table still not implemented | — |
| 26.9+ (unreleased at time of writing) | `SELECT` support for `TimeSeries` tables, `max_over_time`/`min_over_time`, Prometheus HTTP API endpoints | — |

**ClickHouse Cloud:** the engine is **Private Preview** only. On an ordinary
Cloud service, `allow_experimental_time_series_table` is a locked setting —
confirmed live against a real Cloud service on 26.6:
`SETTING_CONSTRAINT_VIOLATION`. There is currently no generally-runnable
Cloud version of this material.

## 3. Settings

| Setting | Purpose | Verified behavior |
|---|---|---|
| `allow_experimental_time_series_table` | Enables `CREATE TABLE ... ENGINE = TimeSeries` | Required — omitting it raises `SUPPORT_IS_DISABLED` (Code 344) |
| `dialect = 'promql'` | Switches the SQL parser to PromQL for **every subsequent statement** in the session | Session-wide; a plain `SELECT '...'` banner after this will fail to parse |
| `promql_table` | Names the `TimeSeries` table bare metric names resolve against | Required before any PromQL query; omitting it errors with "not specified" |
| `allow_experimental_time_series_aggregate_functions` | Gates the 25.6 `timeSeries*ToGrid` SQL aggregate functions, which `prometheusQueryRange()` uses internally | **Inconsistent in testing.** `prometheusQueryRange()` failed once without it (`UNKNOWN_AGGREGATE_FUNCTION`), then succeeded without it on a freshly restarted container running the same version and query. Plain PromQL keyword functions (`rate()`, `topk()`) worked in every test regardless. Set it defensively — see §8.4 |

## 4. Schema — what `CREATE TABLE ... ENGINE = TimeSeries` actually builds

One `TimeSeries` table is four MergeTree-family tables underneath:

| Role | Engine | Sort key | Purpose |
|---|---|---|---|
| samples | `MergeTree` | `(id, timestamp)` | full sample history |
| recent samples | `MergeTree`, partitioned, TTL'd | `(id, timestamp)` | fast recent-data path, bounded by `recent_samples_ttl_seconds` |
| tags | `AggregatingMergeTree` | `(metric_name, id)` | one row per unique (metric_name, tag set) series, with min/max time |
| metrics | `ReplacingMergeTree` | `metric_family_name` | metric metadata (type/unit/help) |

`id` is `Tuple(UInt64, UUID)`, deterministically hashed from
`(metric_name, tags)` — the same label set always maps to the same series id.

The outer (user-facing) schema is fixed and cannot be customized:

```sql
metric_name    String
tags           Map(String, String)
time_series    Array(Tuple(DateTime64(3), Float64))
metric_family  String
type           String
unit           String
help           String
```

There is **no dot-accessor** for the inner tables (`my_table.tags` does not
resolve). Find them via:

```sql
SELECT splitByChar('.', name)[3] AS role, total_rows, formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = currentDatabase()
  AND name LIKE '.inner_id.%.' || (SELECT toString(uuid) FROM system.tables WHERE name = 'my_table' AND database = currentDatabase())
ORDER BY role;
```

## 5. Insert format

**One row per series, not one row per sample.** The full history (or a batch
of new points) for a given `(metric_name, tags)` combination goes into the
`time_series` array in a single INSERT row:

```sql
INSERT INTO my_table (metric_name, tags, time_series)
SELECT
    'cpu_usage_percent',
    map('host', 'web-1', 'region', 'kr'),
    [('2026-09-20 00:00:00.000', 41.2), ('2026-09-20 00:00:15.000', 43.7)];
```

## 6. Reading the data

| Method | Works on 26.8? |
|---|---|
| `SELECT ... FROM my_table` | **No** — `NOT_IMPLEMENTED` (Code 48). Planned for a later release. |
| PromQL via `dialect = 'promql'` | Yes — this is the supported read path today |
| Querying the inner tables directly (via `system.tables` lookup) | Yes, but implementation detail — expect it to be unnecessary once `SELECT` lands |

## 7. PromQL syntax verified working on 26.8

```promql
# instant vector — every series named cpu_usage_percent, latest point
cpu_usage_percent

# label matching: exact and regex
cpu_usage_percent{host="web-1"}
cpu_usage_percent{host=~"web-[12]"}

# range vector — raw points over a window (what rate()/increase() consume)
cpu_usage_percent{host="web-1"}[5m]

# threshold filter, like a Prometheus alerting rule
cpu_usage_percent > 60

# aggregation across the label dimension
avg(cpu_usage_percent)
max by (host) (cpu_usage_percent)
topk(2, cpu_usage_percent)

# counter functions
rate(http_requests_total[5m])
increase(http_requests_total[5m])
sum by (host) (rate(http_requests_total[5m]))

# combining a counter and a gauge in one expression
rate(http_requests_total[5m]) > 1 and cpu_usage_percent > 60
```

**Not available on 26.8:** `max_over_time()`, `min_over_time()` (land in
26.9+). Check `system.functions` and the changelog for your target version
before assuming parity with real Prometheus PromQL.

## 8. Gotchas

1. **PromQL range windows are evaluated relative to the current wall
   clock.** Data that ends "now" at insert time goes stale within a minute
   or two for narrow windows like `[1m]` — not an error, just an empty
   result. Use windows generous enough to tolerate the real delay between
   ingesting and querying (this material uses 5m throughout).
2. **`SET dialect = 'promql'` is session-wide.** Every statement after it,
   including a `SELECT '...'` banner you meant to stay in SQL, is parsed as
   PromQL and will fail. Switch back explicitly (`SET dialect = 'clickhouse'`)
   before running more SQL in the same session/script.
3. **Direct `SELECT` on the table itself does not work on 26.8** — see §6.
4. **`allow_experimental_time_series_aggregate_functions` mattered inconsistently
   for `prometheusQueryRange()`** across otherwise-identical test runs — see §3.
   Set it alongside `allow_experimental_time_series_table` rather than assuming
   either way.

## 9. See also

- [ClickHouse TimeSeries table engine docs](https://clickhouse.com/docs/engines/table-engines/special/time_series)
- [ClickHouse changelog](https://clickhouse.com/docs/whats-new/changelog)
- SQL-native equivalents outside PromQL: `timeSeriesRateToGrid`,
  `timeSeriesIncreaseToGrid`, `timeSeriesResampleToGridWithStaleness`, and
  the rest of the `timeSeries*` family in `system.functions` — these work
  directly on `Array(Tuple(DateTime, Float64))` data without the PromQL
  dialect at all.
