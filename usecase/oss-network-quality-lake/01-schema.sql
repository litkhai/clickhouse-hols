-- OSS network-quality lake: four layers, one database.
--   bronze  ue_trace_raw   as received from the probes
--   silver  ue_trace       cleaned (MV from bronze)
--   gold    cell_kpi_1m    one row per minute x cell (MV from silver)
--   serving cell_rank_now  the 20 rows the NOC map reads (refreshable MV from gold)
-- Verified on ClickHouse 26.9.13.15 (local container, 2026-10-18).

DROP DATABASE IF EXISTS oss_lake SYNC;
-- Atomic: a refreshable MV without APPEND swaps its target table on every refresh.
CREATE DATABASE oss_lake ENGINE = Atomic;

-- "Now" for the demo. Queries read max(anchor_ts) instead of now(), so the data still
-- answers "the last hour" whenever the lab is opened. Production would use now().
-- Append-only: the live feed adds one row per minute it sends.
CREATE TABLE oss_lake.params
(
    anchor_ts DateTime
)
ENGINE = MergeTree ORDER BY anchor_ts;

-- The map grid the generator draws from: three fictional cities, every H3 res-9 cell
-- within 47 rings of each centre (6,769 per city), ordered from the centre outwards.
-- A few cells around one point per city are a coverage hole (weak signal on purpose).
CREATE TABLE oss_lake.grid
(
    city     UInt8,
    idx      UInt32,       -- 0 = centre, grows outwards
    ring     UInt8,        -- H3 grid distance from the centre
    h3       UInt64,
    is_hole  UInt8
)
ENGINE = MergeTree ORDER BY (city, idx);

-- Configuration / inventory (CM): which site and region each cell belongs to. A second
-- source next to the traces; silver looks it up through the dictionary below.
CREATE TABLE oss_lake.cell_inventory
(
    cell        UInt64,
    site_id     String,
    region1     LowCardinality(String),   -- city
    region2     LowCardinality(String),   -- district
    known_weak  UInt8                     -- a known coverage gap, not an incident
)
ENGINE = MergeTree ORDER BY cell;

CREATE DICTIONARY oss_lake.cell_dict
(
    cell UInt64, site_id String, region1 String, region2 String, known_weak UInt8
)
PRIMARY KEY cell
SOURCE(CLICKHOUSE(DB 'oss_lake' TABLE 'cell_inventory'))
LAYOUT(HASHED())
LIFETIME(0);

-- ---------------------------------------------------------------- bronze
-- Exactly what the probes send: H3 as a string, the IMSI as the vendor's
-- ciphertext (44-char base64), every measurement Nullable, CQI as text.
CREATE TABLE oss_lake.ue_trace_raw
(
    event_ts   DateTime64(3),
    h3_res09   Nullable(String),
    imsi       Nullable(String),
    rsrp       Nullable(Float64),   -- dBm
    rsrq       Nullable(Float64),   -- dB
    sinr       Nullable(Float64),   -- dB
    cqi        Nullable(String),
    pci        Nullable(UInt16),
    probe      LowCardinality(String),
    ingest_ts  DateTime64(3) DEFAULT now64(3)
)
ENGINE = MergeTree
PARTITION BY toDate(event_ts)
ORDER BY event_ts
TTL toDateTime(event_ts) + INTERVAL 3 DAY;

-- ---------------------------------------------------------------- silver
-- Typed and de-identified: H3 as a number, a hash instead of the ciphertext,
-- Float32 metrics. Only rsrp stays Nullable: a missing radio report is not 0 dBm.
CREATE TABLE oss_lake.ue_trace
(
    event_ts   DateTime64(3),
    h3         UInt64,
    imsi_hash  UInt64,
    rsrp       Nullable(Float32),
    rsrq       Float32,
    sinr       Float32,
    cqi        UInt8,
    region1    LowCardinality(String),
    region2    LowCardinality(String)
)
ENGINE = MergeTree
PARTITION BY toDate(event_ts)
ORDER BY (event_ts, h3);

-- Rows without a cell or a subscriber cannot be placed or counted: silver drops them.
CREATE MATERIALIZED VIEW oss_lake.ue_trace_mv TO oss_lake.ue_trace AS
SELECT
    event_ts,
    stringToH3(assumeNotNull(h3_res09))       AS h3,
    cityHash64(assumeNotNull(imsi))           AS imsi_hash,
    CAST(rsrp AS Nullable(Float32))           AS rsrp,
    toFloat32(ifNull(rsrq, 0))                AS rsrq,
    toFloat32(ifNull(sinr, 0))                AS sinr,
    toUInt8OrZero(ifNull(cqi, ''))            AS cqi,
    -- a measurement gets a place name from the inventory
    dictGet('oss_lake.cell_dict', 'region1', h3) AS region1,
    dictGet('oss_lake.cell_dict', 'region2', h3) AS region2
FROM oss_lake.ue_trace_raw
WHERE h3_res09 IS NOT NULL AND imsi IS NOT NULL;

-- ---------------------------------------------------------------- gold
-- One row per (minute, cell). Users are a uniq state so any time range can be merged;
-- the rest are plain sums. Column names differ from the aliases queries use
-- (users_st vs users): an alias equal to the column inside its own aggregate is
-- ILLEGAL_AGGREGATION.
CREATE TABLE oss_lake.cell_kpi_1m
(
    bucket     DateTime,
    cell       UInt64,
    users_st   AggregateFunction(uniq, UInt64),
    samples_n  SimpleAggregateFunction(sum, UInt64),
    rsrp_n     SimpleAggregateFunction(sum, UInt64),   -- samples that carried rsrp
    rsrp_sum   SimpleAggregateFunction(sum, Float64),
    poor_n     SimpleAggregateFunction(sum, UInt64)    -- rsrp < -100 dBm
)
ENGINE = AggregatingMergeTree
ORDER BY (bucket, cell);

CREATE MATERIALIZED VIEW oss_lake.cell_kpi_1m_mv TO oss_lake.cell_kpi_1m AS
SELECT
    toStartOfMinute(event_ts)  AS bucket,
    h3                         AS cell,
    uniqState(imsi_hash)       AS users_st,
    count()                    AS samples_n,
    count(rsrp)                AS rsrp_n,
    sum(ifNull(rsrp, 0))       AS rsrp_sum,
    countIf(rsrp < -100)       AS poor_n
FROM oss_lake.ue_trace
GROUP BY bucket, cell;

-- Gold along a second axis: geography. Minute x district, from the same silver rows.
CREATE TABLE oss_lake.region_kpi_1m
(
    bucket     DateTime,
    region1    LowCardinality(String),
    region2    LowCardinality(String),
    users_st   AggregateFunction(uniq, UInt64),
    samples_n  SimpleAggregateFunction(sum, UInt64),
    rsrp_n     SimpleAggregateFunction(sum, UInt64),
    rsrp_sum   SimpleAggregateFunction(sum, Float64),
    poor_n     SimpleAggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY (bucket, region1, region2);

CREATE MATERIALIZED VIEW oss_lake.region_kpi_1m_mv TO oss_lake.region_kpi_1m AS
SELECT
    toStartOfMinute(event_ts)  AS bucket,
    region1, region2,
    uniqState(imsi_hash)       AS users_st,
    count()                    AS samples_n,
    count(rsrp)                AS rsrp_n,
    sum(ifNull(rsrp, 0))       AS rsrp_sum,
    countIf(rsrp < -100)       AS poor_n
FROM oss_lake.ue_trace
GROUP BY bucket, region1, region2;

-- Gold builds on gold: a 10-minute cell rollup fed by the 1-minute one (each insert into
-- cell_kpi_1m cascades here), so raw rows are aggregated once. Not a refreshable MV with
-- APPEND: a window wider than the refresh interval would be inserted twice.
CREATE TABLE oss_lake.cell_kpi_10m
(
    bucket     DateTime,
    cell       UInt64,
    users_st   AggregateFunction(uniq, UInt64),
    samples_n  SimpleAggregateFunction(sum, UInt64),
    rsrp_n     SimpleAggregateFunction(sum, UInt64),
    rsrp_sum   SimpleAggregateFunction(sum, Float64),
    poor_n     SimpleAggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY (bucket, cell);

CREATE MATERIALIZED VIEW oss_lake.cell_kpi_10m_mv TO oss_lake.cell_kpi_10m AS
SELECT
    toStartOfTenMinutes(k.bucket)  AS bucket,
    k.cell                         AS cell,
    uniqMergeState(k.users_st)     AS users_st,
    sum(k.samples_n)               AS samples_n,
    sum(k.rsrp_n)                  AS rsrp_n,
    sum(k.rsrp_sum)                AS rsrp_sum,
    sum(k.poor_n)                  AS poor_n
FROM oss_lake.cell_kpi_1m AS k
GROUP BY bucket, cell;

-- ---------------------------------------------------------------- serving
-- The 20 rows the NOC map reads: top 10 cells by users and the 10 with the weakest
-- average signal (cells with at least 30 rsrp samples), over the last hour.
CREATE TABLE oss_lake.cell_rank_now
(
    list         LowCardinality(String),   -- 'users' or 'signal'
    rnk          UInt8,
    cell         UInt64,
    users        UInt64,
    samples      UInt64,
    avg_rsrp     Float64,
    poor_pct     Float64,
    window_end   DateTime
)
ENGINE = MergeTree ORDER BY (list, rnk);

-- No APPEND: every refresh replaces the 20 rows.
CREATE MATERIALIZED VIEW oss_lake.cell_rank_rmv
REFRESH EVERY 1 MINUTE TO oss_lake.cell_rank_now AS
WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t
SELECT
    lr.1 AS list, lr.2 AS rnk, cell, users, samples, avg_rsrp, poor_pct, t AS window_end
FROM
(
    SELECT
        cell,
        uniqMerge(users_st)                              AS users,
        sum(samples_n)                                   AS samples,
        round(sum(rsrp_sum) / sum(rsrp_n), 1)            AS avg_rsrp,
        round(100 * sum(poor_n) / sum(rsrp_n), 1)        AS poor_pct,
        sum(rsrp_n) >= 30                                AS eligible,
        row_number() OVER (ORDER BY users DESC, cell)    AS r_users,
        row_number() OVER (PARTITION BY eligible ORDER BY sum(rsrp_sum) / sum(rsrp_n), cell) AS r_signal
    FROM oss_lake.cell_kpi_1m
    WHERE bucket >= t - INTERVAL 1 HOUR AND bucket < t
    GROUP BY cell
)
ARRAY JOIN [('users', r_users), ('signal', if(eligible, r_signal, 999))] AS lr
WHERE lr.2 <= 10;

-- Reads go through a read-only user (the demo server's reader).
DROP USER IF EXISTS oss_reader;
CREATE USER oss_reader IDENTIFIED WITH no_password SETTINGS readonly = 1;
GRANT SELECT ON oss_lake.* TO oss_reader;
GRANT dictGet ON oss_lake.* TO oss_reader;
GRANT SELECT ON system.parts TO oss_reader;               -- layer sizes
GRANT SELECT ON system.asynchronous_metrics TO oss_reader; -- machine line in the snapshot
