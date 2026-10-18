-- The one pitfall, reproduced by hand (tools/hol does not run this file; it fails on purpose).
-- An AggregateFunction column whose argument type no longer matches its source.
--
-- Measured 2026-10-18 (local containers 25.8.33.6, 26.6.8.7, 26.8.22.13, 26.9.13.15):
-- CREATE MATERIALIZED VIEW already refuses a mismatch it can see (avgState over a
-- Nullable(Float32) into AggregateFunction(avg, Float32) -> CANNOT_CONVERT_TYPE at CREATE).
-- It cannot see one that arrives later: make the source column Nullable with ALTER and the
-- ALTER succeeds, then every INSERT fails -- and the source row is written anyway, so the
-- source keeps growing while the aggregate stops. Run in a scratch database:
--
--   clickhouse-client -n < pitfall.sql

DROP DATABASE IF EXISTS oss_pitfall SYNC;
CREATE DATABASE oss_pitfall;

CREATE TABLE oss_pitfall.trace (event_ts DateTime, cell UInt64, rsrp Float32)
ENGINE = MergeTree ORDER BY event_ts;

CREATE TABLE oss_pitfall.kpi
(
    bucket       DateTime,
    cell         UInt64,
    avg_rsrp_st  AggregateFunction(avg, Float32)
)
ENGINE = AggregatingMergeTree ORDER BY (bucket, cell);

CREATE MATERIALIZED VIEW oss_pitfall.kpi_mv TO oss_pitfall.kpi AS
SELECT toStartOfMinute(event_ts) AS bucket, cell, avgState(rsrp) AS avg_rsrp_st
FROM oss_pitfall.trace GROUP BY bucket, cell;

INSERT INTO oss_pitfall.trace VALUES (now(), 1, -90);       -- ok: trace 1 row, kpi 1 row

-- "some probes omit rsrp, let it be NULL" -- accepted without a word about kpi_mv
ALTER TABLE oss_pitfall.trace MODIFY COLUMN rsrp Nullable(Float32);

SELECT 'trace' AS t, count() FROM oss_pitfall.trace UNION ALL SELECT 'kpi', count() FROM oss_pitfall.kpi;

-- fails: Code: 70 ... Conversion from AggregateFunction(avg, Nullable(Float32)) to
-- AggregateFunction(avg, Float32) is not supported ... while pushing to view oss_pitfall.kpi_mv
INSERT INTO oss_pitfall.trace VALUES (now(), 1, -91);

-- not reached with clickhouse-client -n (it stops at the error); run it by hand:
-- trace has 2 rows, kpi still 1.
SELECT 'trace' AS t, count() FROM oss_pitfall.trace UNION ALL SELECT 'kpi', count() FROM oss_pitfall.kpi;

-- the fix: state type follows the source (AggregateFunction(avg, Nullable(Float32))), or the
-- MV feeds a non-Nullable argument (avgState(assumeNotNull(rsrp)) with WHERE rsrp IS NOT NULL),
-- or, as the lab's gold layer does, plain sums: count(rsrp) and sum(ifNull(rsrp, 0)).
-- DROP DATABASE oss_pitfall SYNC;
