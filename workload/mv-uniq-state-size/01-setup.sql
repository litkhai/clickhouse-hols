-- 01-setup.sql: a raw table, a 1-minute rollup fed by a materialized view on the raw table,
-- and a 10-minute rollup fed by a materialized view on the 1-minute rollup (cascading).
--
-- The rollup holds the same distinct-user count nine times (one column per state function and
-- input type) so that system.parts_columns can give each one's size side by side. A real rollup
-- would hold one of them. Every rollup column is pinned to CODEC(LZ4) so the compressed sizes
-- do not depend on the build's default codec; uncompressed sizes are the state bytes themselves.

CREATE DATABASE IF NOT EXISTS mv_uniq;

-- Raw events: page views. The same user appears as UInt32, UInt64 and a 32-character String.
CREATE TABLE mv_uniq.events
(
    ts         DateTime('UTC')        CODEC(LZ4),
    kind       LowCardinality(String) CODEC(LZ4),
    page       UInt32                 CODEC(LZ4),
    user_u32   UInt32                 CODEC(LZ4),
    user_u64   UInt64                 CODEC(LZ4),
    user_str   String                 CODEC(LZ4),
    latency_ms Float32                CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY ts;

CREATE TABLE mv_uniq.rollup_1m
(
    bucket       DateTime('UTC')                           CODEC(LZ4),
    kind         LowCardinality(String)                    CODEC(LZ4),
    page         UInt32                                    CODEC(LZ4),
    events       SimpleAggregateFunction(sum, UInt64)      CODEC(LZ4),
    latency_sum  SimpleAggregateFunction(sum, Float64)     CODEC(LZ4),
    u_uniq_str   AggregateFunction(uniq, String)           CODEC(LZ4),
    u_uniq_u64   AggregateFunction(uniq, UInt64)           CODEC(LZ4),
    u_uniq_u32   AggregateFunction(uniq, UInt32)           CODEC(LZ4),
    u_comb_u64   AggregateFunction(uniqCombined, UInt64)   CODEC(LZ4),
    u_comb12_u64 AggregateFunction(uniqCombined(12), UInt64) CODEC(LZ4),
    u_hll12_u64  AggregateFunction(uniqHLL12, UInt64)      CODEC(LZ4),
    u_exact_str  AggregateFunction(uniqExact, String)      CODEC(LZ4),
    u_exact_u64  AggregateFunction(uniqExact, UInt64)      CODEC(LZ4),
    u_exact_u32  AggregateFunction(uniqExact, UInt32)      CODEC(LZ4)
)
ENGINE = AggregatingMergeTree
ORDER BY (bucket, kind, page)
SETTINGS min_bytes_for_wide_part = 0;

CREATE MATERIALIZED VIEW mv_uniq.mv_1m TO mv_uniq.rollup_1m AS
SELECT
    toStartOfMinute(ts)              AS bucket,
    kind,
    page,
    count()                          AS events,
    sum(toFloat64(latency_ms))       AS latency_sum,
    uniqState(user_str)              AS u_uniq_str,
    uniqState(user_u64)              AS u_uniq_u64,
    uniqState(user_u32)              AS u_uniq_u32,
    uniqCombinedState(user_u64)      AS u_comb_u64,
    uniqCombinedState(12)(user_u64)  AS u_comb12_u64,
    uniqHLL12State(user_u64)         AS u_hll12_u64,
    uniqExactState(user_str)         AS u_exact_str,
    uniqExactState(user_u64)         AS u_exact_u64,
    uniqExactState(user_u32)         AS u_exact_u32
FROM mv_uniq.events
GROUP BY bucket, kind, page;

-- Same columns, codecs and settings as the 1-minute rollup.
CREATE TABLE mv_uniq.rollup_10m AS mv_uniq.rollup_1m
ENGINE = AggregatingMergeTree
ORDER BY (bucket, kind, page)
SETTINGS min_bytes_for_wide_part = 0;

-- Cascading: the source is the 1-minute rollup, so this view sees each block the 1-minute view
-- writes and merges its partial states into 10-minute states. The raw rows are aggregated once.
CREATE MATERIALIZED VIEW mv_uniq.mv_10m TO mv_uniq.rollup_10m AS
SELECT
    toStartOfTenMinutes(bucket)               AS bucket,
    kind,
    page,
    sum(events)                               AS events,
    sum(latency_sum)                          AS latency_sum,
    uniqMergeState(u_uniq_str)                AS u_uniq_str,
    uniqMergeState(u_uniq_u64)                AS u_uniq_u64,
    uniqMergeState(u_uniq_u32)                AS u_uniq_u32,
    uniqCombinedMergeState(u_comb_u64)        AS u_comb_u64,
    uniqCombinedMergeState(12)(u_comb12_u64)  AS u_comb12_u64,
    uniqHLL12MergeState(u_hll12_u64)          AS u_hll12_u64,
    uniqExactMergeState(u_exact_str)          AS u_exact_str,
    uniqExactMergeState(u_exact_u64)          AS u_exact_u64,
    uniqExactMergeState(u_exact_u32)          AS u_exact_u32
FROM mv_uniq.rollup_1m
GROUP BY bucket, kind, page;
