-- ============================================================================
-- CostKeeper: ClickHouse Cloud Cost Monitoring & Alerting System
-- ============================================================================
-- Description: Automated cost monitoring with hourly analysis and alerts
-- Version: 1.0
-- Date: 2025-12-06
-- ============================================================================
--
-- Configuration Variables (replaced by setup script):
--   ${DATABASE_NAME}            - Database name (default: costkeeper)
--   ${SERVICE_NAME}             - Service display name (e.g., production)
--   ${CHC_ORG_ID}               - CHC Organization ID (UUID)
--   ${CHC_SERVICE_ID}           - CHC Service ID (UUID)
--   ${CHC_API_KEY_ID}           - CHC API Key ID (used as Bearer token)
--   ${CHC_API_KEY_SECRET}       - CHC API Key Secret
--   ${ALERT_THRESHOLD_PCT}      - Alert threshold percentage (e.g., 20.0)
--   ${WARNING_THRESHOLD_PCT}    - Warning threshold percentage (e.g., 30.0)
--   ${CRITICAL_THRESHOLD_PCT}   - Critical threshold percentage (e.g., 50.0)
--   ${DATA_RETENTION_DAYS}      - Data retention in days (e.g., 365)
--   ${ALERT_RETENTION_DAYS}     - Alert retention in days (e.g., 90)
--
-- Note: CPU/Memory allocation is retrieved dynamically from CHC API
--
-- ============================================================================


-- ############################################################################
-- PART 1: Database Creation and Cleanup
-- ############################################################################

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS ${DATABASE_NAME};

-- Step 1: Drop Materialized Views (dependency order)
DROP VIEW IF EXISTS ${DATABASE_NAME}.mv_alerts;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_hourly_analysis;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_hourly_metrics;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_metrics_15min;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_daily_billing;

-- Step 2: Drop Regular Views
DROP VIEW IF EXISTS ${DATABASE_NAME}.v_dashboard;
DROP VIEW IF EXISTS ${DATABASE_NAME}.v_alerts;

-- Step 3: Backup Data (optional - uncomment if needed)
-- CREATE TABLE ${DATABASE_NAME}.hourly_analysis_backup AS SELECT * FROM ${DATABASE_NAME}.hourly_analysis;
-- CREATE TABLE ${DATABASE_NAME}.alerts_backup AS SELECT * FROM ${DATABASE_NAME}.alerts;

-- Step 4: Drop Tables (Warning: Data loss!)
DROP TABLE IF EXISTS ${DATABASE_NAME}.metrics_15min;
DROP TABLE IF EXISTS ${DATABASE_NAME}.daily_billing;
DROP TABLE IF EXISTS ${DATABASE_NAME}.hourly_metrics;
DROP TABLE IF EXISTS ${DATABASE_NAME}.hourly_analysis;
DROP TABLE IF EXISTS ${DATABASE_NAME}.alerts;


-- ############################################################################
-- PART 2: CHC API Integration
-- ############################################################################
-- Note: ClickHouse Cloud doesn't support CREATE FUNCTION for SQL UDFs
-- Instead, we inline the API call directly in each RMV query


-- ############################################################################
-- PART 3: Table Schema
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Layer 0: Daily Billing (Cloud API Data)
-- ----------------------------------------------------------------------------
CREATE TABLE ${DATABASE_NAME}.daily_billing
(
    date Date,
    service_id String,
    service_name String,
    total_chc Float64,
    compute_chc Float64,
    storage_chc Float64,
    network_chc Float64,
    api_fetched_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = ReplacingMergeTree(api_fetched_at)
ORDER BY (date, service_id)
TTL date + INTERVAL ${DATA_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- Layer 0: 15-Minute Raw Metrics (Frequent Collection to Avoid Data Loss)
-- ----------------------------------------------------------------------------
-- ⚠️ This table collects metrics every 15 minutes to prevent data loss
-- due to ClickHouse Cloud's aggressive cleanup of system.asynchronous_metric_log (~33min retention)
CREATE TABLE ${DATABASE_NAME}.metrics_15min
(
    collected_at DateTime,
    allocated_cpu Float64,
    allocated_memory_gb Float64,

    -- CPU metrics
    cpu_usage_avg Float64,
    cpu_usage_p50 Float64,
    cpu_usage_p90 Float64,
    cpu_usage_p99 Float64,
    cpu_usage_max Float64,
    cpu_user_cores Float64,
    cpu_system_cores Float64,

    -- Memory metrics
    memory_used_avg_gb Float64,
    memory_used_p99_gb Float64,
    memory_used_max_gb Float64,
    memory_usage_pct_avg Float64,
    memory_usage_pct_p99 Float64,
    memory_usage_pct_max Float64,

    -- Disk metrics
    disk_read_bytes Float64,
    disk_write_bytes Float64,
    disk_total_gb Float64,
    disk_used_gb Float64,
    disk_usage_pct Float64,

    -- Network metrics
    network_rx_bytes Float64,
    network_tx_bytes Float64,

    -- Load metrics
    load_avg_1m Float64,
    load_avg_5m Float64,
    processes_running_avg Float64,

    -- Metadata
    service_name String DEFAULT '${SERVICE_NAME}'
)
ENGINE = SharedMergeTree()
ORDER BY (collected_at, service_name)
TTL collected_at + INTERVAL ${DATA_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- Layer 1: Hourly Metrics (Aggregated from 15-min data)
-- ----------------------------------------------------------------------------
CREATE TABLE ${DATABASE_NAME}.hourly_metrics
(
    hour DateTime,
    allocated_cpu Float64,
    allocated_memory_gb Float64,

    -- CPU metrics
    cpu_usage_avg Float64,
    cpu_usage_p50 Float64,
    cpu_usage_p90 Float64,
    cpu_usage_p99 Float64,
    cpu_usage_max Float64,
    cpu_user_cores Float64,
    cpu_system_cores Float64,

    -- Memory metrics
    memory_used_avg_gb Float64,
    memory_used_p99_gb Float64,
    memory_used_max_gb Float64,
    memory_usage_pct_avg Float64,
    memory_usage_pct_p99 Float64,
    memory_usage_pct_max Float64,

    -- Disk metrics
    disk_read_bytes Float64,
    disk_write_bytes Float64,
    disk_total_gb Float64,
    disk_used_gb Float64,
    disk_usage_pct Float64,

    -- Network metrics
    network_rx_bytes Float64,
    network_tx_bytes Float64,

    -- Load metrics
    load_avg_1m Float64,
    load_avg_5m Float64,
    processes_running_avg Float64,

    -- Metadata
    service_name String DEFAULT '${SERVICE_NAME}'
)
ENGINE = SharedMergeTree()
ORDER BY (hour, service_name)
TTL hour + INTERVAL ${DATA_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;

-- ⚠️ NOTE: Initial data population is NOT needed
-- Reason: system.asynchronous_metric_log in ClickHouse Cloud only retains ~1 hour of data
-- The RMV (Refreshable Materialized View) will automatically collect data starting from
-- the first hour after setup. Historical data collection is not possible.

-- ----------------------------------------------------------------------------
-- Layer 2: Hourly Analysis (Main Analysis Table)
-- ----------------------------------------------------------------------------
CREATE TABLE ${DATABASE_NAME}.hourly_analysis
(
    -- Time information
    hour DateTime,
    service_name String DEFAULT '${SERVICE_NAME}',

    -- Daily billing information (from Cloud API)
    daily_total_chc Float64,
    daily_compute_chc Float64,
    daily_storage_chc Float64,
    daily_network_chc Float64,

    -- Estimated hourly costs (equally distributed)
    estimated_hourly_total_chc Float64,
    estimated_hourly_compute_chc Float64,
    estimated_hourly_storage_chc Float64,
    estimated_hourly_network_chc Float64,
    cost_per_cpu_core_hour Float64,

    -- Resource allocation and usage
    allocated_cpu Float64,
    allocated_memory_gb Float64,
    cpu_usage_avg Float64,
    cpu_usage_p99 Float64,
    cpu_usage_max Float64,
    memory_usage_pct_avg Float64,
    memory_usage_pct_p99 Float64,

    -- Efficiency metrics
    cpu_efficiency_pct Float64,
    memory_efficiency_pct Float64,
    overall_efficiency_pct Float64,

    -- ========================================
    -- Comparison baseline (lagInFrame based, no JOIN)
    -- ========================================
    prev_1h_cpu_usage Float64,      -- 1 hour ago
    prev_1h_hourly_cost Float64,
    prev_3h_cpu_usage Float64,      -- 3 hours ago
    prev_3h_hourly_cost Float64,
    prev_24h_cpu_usage Float64,     -- Yesterday same time (24 hours ago)
    prev_24h_hourly_cost Float64,

    -- ========================================
    -- Change rates (%)
    -- ========================================
    pct_change_1h_cpu Float64,
    pct_change_1h_cost Float64,
    pct_change_3h_cpu Float64,
    pct_change_3h_cost Float64,
    pct_change_24h_cpu Float64,
    pct_change_24h_cost Float64,

    -- ========================================
    -- Alert flags (${ALERT_THRESHOLD_PCT}% threshold)
    -- ========================================
    alert_cpu_spike_1h UInt8,
    alert_cpu_spike_3h UInt8,
    alert_cpu_spike_24h UInt8,
    alert_cost_spike_1h UInt8,
    alert_cost_spike_3h UInt8,
    alert_cost_spike_24h UInt8,
    alert_any UInt8
)
ENGINE = SharedMergeTree()
ORDER BY (hour, service_name)
TTL hour + INTERVAL ${DATA_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;

-- ⚠️ NOTE: Initial data population is NOT needed
-- Reason: hourly_analysis depends on hourly_metrics, which is populated by RMV
-- RMV 2 (hourly_metrics) and RMV 3 (hourly_analysis) will automatically work together
-- to collect and analyze data starting from the first hour after setup.

-- ----------------------------------------------------------------------------
-- Layer 3: Alerts Table
-- ----------------------------------------------------------------------------
CREATE TABLE ${DATABASE_NAME}.alerts
(
    alert_id UUID DEFAULT generateUUIDv4(),
    alert_time DateTime64(3) DEFAULT now64(3),
    hour DateTime,

    -- Alert classification
    alert_type LowCardinality(String),        -- 'cpu', 'cost'
    comparison_period LowCardinality(String), -- '1h', '3h', '24h'
    severity LowCardinality(String),          -- 'info', 'warning', 'critical'

    -- Value information
    current_value Float64,
    comparison_value Float64,
    pct_change Float64,
    threshold_pct Float64 DEFAULT ${ALERT_THRESHOLD_PCT},

    -- Cost impact
    estimated_hourly_chc Float64,
    potential_daily_impact_chc Float64,

    -- Alert message
    message String,

    -- Status management
    acknowledged UInt8 DEFAULT 0,
    acknowledged_at Nullable(DateTime64(3)),

    service_name String DEFAULT '${SERVICE_NAME}'
)
ENGINE = SharedMergeTree()
ORDER BY (alert_time, hour, alert_type, comparison_period)
TTL alert_time + INTERVAL ${ALERT_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;


-- ############################################################################
-- PART 4: Refreshable Materialized Views
-- ############################################################################

-- ----------------------------------------------------------------------------
-- RMV 1: Daily Billing (from CHC API)
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_daily_billing
REFRESH EVERY 1 DAY OFFSET 1 HOUR APPEND
TO ${DATABASE_NAME}.daily_billing
AS
SELECT
    toDate(JSONExtractString(cost_item, 'date')) AS date,
    JSONExtractString(cost_item, 'serviceId') AS service_id,
    JSONExtractString(cost_item, 'entityName') AS service_name,
    JSONExtractFloat(cost_item, 'totalCHC') AS total_chc,
    JSONExtractFloat(JSONExtractRaw(cost_item, 'metrics'), 'computeCHC') AS compute_chc,
    JSONExtractFloat(JSONExtractRaw(cost_item, 'metrics'), 'storageCHC') AS storage_chc,
    (JSONExtractFloat(JSONExtractRaw(cost_item, 'metrics'), 'publicDataTransferCHC') +
     JSONExtractFloat(JSONExtractRaw(cost_item, 'metrics'), 'interRegionTier1DataTransferCHC') +
     JSONExtractFloat(JSONExtractRaw(cost_item, 'metrics'), 'dataTransferCHC')) AS network_chc
    -- ⚠️ api_fetched_at removed → table DEFAULT now64(3) is used
FROM (
    SELECT arrayJoin(JSONExtractArrayRaw(
        JSONExtractRaw(json, 'result'), 'costs'
    )) AS cost_item
    FROM url(
        concat(
            'https://api.clickhouse.cloud/v1/organizations/${CHC_ORG_ID}/usageCost',
            '?from_date=', formatDateTime(now() - toIntervalDay(7), '%Y-%m-%d'),
            '&to_date=', formatDateTime(now(), '%Y-%m-%d')
        ),
        'JSONAsString',
        'json String',
        headers('Authorization' = concat('Basic ', base64Encode('${CHC_API_KEY_ID}:${CHC_API_KEY_SECRET}')))
    )
)
WHERE JSONExtractString(cost_item, 'entityType') = 'service'
  AND JSONExtractString(cost_item, 'serviceId') = '${CHC_SERVICE_ID}';


-- ----------------------------------------------------------------------------
-- RMV 2: 15-Minute Metrics Collection (from System Tables)
-- ----------------------------------------------------------------------------
-- ⚠️ CRITICAL: Collects every 15 minutes to avoid data loss
-- ClickHouse Cloud's system.asynchronous_metric_log has ~33min retention
-- This RMV captures data before it gets purged
CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_metrics_15min
REFRESH EVERY 15 MINUTE APPEND
TO ${DATABASE_NAME}.metrics_15min
AS
WITH
    target_period AS (
        SELECT now() - INTERVAL 15 MINUTE as start_time
    ),
    metrics_agg AS (
        SELECT
            toStartOfFifteenMinutes(now()) as collected_at,

            -- Allocated resources from CGroup metrics
            avgIf(value, metric = 'CGroupMaxCPU') as allocated_cpu,
            avgIf(value, metric = 'CGroupMemoryTotal') / (1024 * 1024 * 1024) as allocated_memory_gb,

            -- CPU metrics
            avgIf(value, metric = 'CGroupUserTimeNormalized') +
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_avg,

            quantileIf(0.5)(value, metric = 'CGroupUserTimeNormalized') +
            quantileIf(0.5)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p50,

            quantileIf(0.9)(value, metric = 'CGroupUserTimeNormalized') +
            quantileIf(0.9)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p90,

            quantileIf(0.99)(value, metric = 'CGroupUserTimeNormalized') +
            quantileIf(0.99)(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_p99,

            maxIf(value, metric = 'CGroupUserTimeNormalized') +
            maxIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_max,

            avgIf(value, metric = 'CGroupUserTimeNormalized') as cpu_user_cores,
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_system_cores,

            -- Memory metrics (using CGroup metrics)
            avgIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_avg_gb,
            quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_p99_gb,
            maxIf(value, metric = 'CGroupMemoryUsed') / (1024 * 1024 * 1024) as memory_used_max_gb,

            (avgIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_avg,
            (quantileIf(0.99)(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_p99,
            (maxIf(value, metric = 'CGroupMemoryUsed') / avgIf(value, metric = 'CGroupMemoryTotal')) * 100 as memory_usage_pct_max,

            -- Disk metrics
            sumIf(value, metric LIKE 'BlockReadBytes%') as disk_read_bytes,
            sumIf(value, metric LIKE 'BlockWriteBytes%') as disk_write_bytes,
            maxIf(value, metric = 'FilesystemMainPathTotalBytes') / (1024 * 1024 * 1024) as disk_total_gb,
            maxIf(value, metric = 'FilesystemMainPathUsedBytes') / (1024 * 1024 * 1024) as disk_used_gb,
            (maxIf(value, metric = 'FilesystemMainPathUsedBytes') / maxIf(value, metric = 'FilesystemMainPathTotalBytes')) * 100 as disk_usage_pct,

            -- Network metrics
            sumIf(value, metric = 'NetworkReceiveBytes_eth0') as network_rx_bytes,
            sumIf(value, metric = 'NetworkSendBytes_eth0') as network_tx_bytes,

            -- Load Average
            avgIf(value, metric = 'LoadAverage1') as load_avg_1m,
            avgIf(value, metric = 'LoadAverage5') as load_avg_5m,
            avgIf(value, metric = 'OSProcessesRunning') as processes_running_avg

        FROM system.asynchronous_metric_log
        WHERE event_time >= (SELECT start_time FROM target_period)
          AND event_time < now()
    )
SELECT
    collected_at,
    allocated_cpu,
    allocated_memory_gb,
    cpu_usage_avg,
    cpu_usage_p50,
    cpu_usage_p90,
    cpu_usage_p99,
    cpu_usage_max,
    cpu_user_cores,
    cpu_system_cores,
    memory_used_avg_gb,
    memory_used_p99_gb,
    memory_used_max_gb,
    memory_usage_pct_avg,
    memory_usage_pct_p99,
    memory_usage_pct_max,
    disk_read_bytes,
    disk_write_bytes,
    disk_total_gb,
    disk_used_gb,
    disk_usage_pct,
    network_rx_bytes,
    network_tx_bytes,
    load_avg_1m,
    load_avg_5m,
    processes_running_avg,
    '${SERVICE_NAME}' as service_name
FROM metrics_agg;


-- ----------------------------------------------------------------------------
-- RMV 3: Hourly Metrics Aggregation (from 15-min data)
-- ----------------------------------------------------------------------------
-- ⚠️ This RMV aggregates four 15-minute periods into one hour
CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_hourly_metrics
REFRESH EVERY 1 HOUR OFFSET 2 MINUTE APPEND
TO ${DATABASE_NAME}.hourly_metrics
AS
WITH
    target_hour AS (
        SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
    )
SELECT
    (SELECT h FROM target_hour) as hour,

    -- Allocated resources (avg across 4 periods)
    avg(allocated_cpu) as allocated_cpu,
    avg(allocated_memory_gb) as allocated_memory_gb,

    -- CPU metrics (aggregate across 4 periods)
    avg(cpu_usage_avg) as cpu_usage_avg,
    avg(cpu_usage_p50) as cpu_usage_p50,
    avg(cpu_usage_p90) as cpu_usage_p90,
    avg(cpu_usage_p99) as cpu_usage_p99,
    max(cpu_usage_max) as cpu_usage_max,
    avg(cpu_user_cores) as cpu_user_cores,
    avg(cpu_system_cores) as cpu_system_cores,

    -- Memory metrics
    avg(memory_used_avg_gb) as memory_used_avg_gb,
    avg(memory_used_p99_gb) as memory_used_p99_gb,
    max(memory_used_max_gb) as memory_used_max_gb,
    avg(memory_usage_pct_avg) as memory_usage_pct_avg,
    avg(memory_usage_pct_p99) as memory_usage_pct_p99,
    max(memory_usage_pct_max) as memory_usage_pct_max,

    -- Disk metrics (sum for bytes, avg for usage %)
    sum(disk_read_bytes) as disk_read_bytes,
    sum(disk_write_bytes) as disk_write_bytes,
    avg(disk_total_gb) as disk_total_gb,
    avg(disk_used_gb) as disk_used_gb,
    avg(disk_usage_pct) as disk_usage_pct,

    -- Network metrics (sum bytes transferred)
    sum(network_rx_bytes) as network_rx_bytes,
    sum(network_tx_bytes) as network_tx_bytes,

    -- Load metrics (avg)
    avg(load_avg_1m) as load_avg_1m,
    avg(load_avg_5m) as load_avg_5m,
    avg(processes_running_avg) as processes_running_avg,

    service_name
FROM ${DATABASE_NAME}.metrics_15min
WHERE collected_at >= (SELECT h FROM target_hour)
  AND collected_at < (SELECT h + INTERVAL 1 HOUR FROM target_hour)
GROUP BY service_name;


-- ----------------------------------------------------------------------------
-- RMV 4: Hourly Analysis
-- ----------------------------------------------------------------------------

CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_hourly_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE APPEND
TO ${DATABASE_NAME}.hourly_analysis
AS
WITH
target_hour AS (
    SELECT toStartOfHour(now() - INTERVAL 1 HOUR) AS h
),
metrics_with_lag AS (
    SELECT
        m.hour,
        m.service_name,
        m.allocated_cpu,
        m.allocated_memory_gb,
        m.cpu_usage_avg,
        m.cpu_usage_p99,
        m.cpu_usage_max,
        m.memory_usage_pct_avg,
        m.memory_usage_pct_p99,

        -- billing information join
        coalesce(d.total_chc, 0) AS daily_total_chc,
        coalesce(d.compute_chc, 0) AS daily_compute_chc,
        coalesce(d.storage_chc, 0) AS daily_storage_chc,
        coalesce(d.network_chc, 0) AS daily_network_chc,

        -- Calculate previous values with lagInFrame (No Self JOIN!)
        lagInFrame(m.cpu_usage_avg, 1) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_1h_cpu,
        lagInFrame(m.cpu_usage_avg, 3) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_3h_cpu,
        lagInFrame(m.cpu_usage_avg, 24) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_24h_cpu,

        lagInFrame(coalesce(d.total_chc, 0), 1) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_1h_daily_cost,
        lagInFrame(coalesce(d.total_chc, 0), 3) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_3h_daily_cost,
        lagInFrame(coalesce(d.total_chc, 0), 24) OVER (PARTITION BY m.service_name ORDER BY m.hour ASC) AS prev_24h_daily_cost

    FROM ${DATABASE_NAME}.hourly_metrics AS m
    LEFT JOIN ${DATABASE_NAME}.daily_billing AS d
        ON toDate(m.hour) = d.date
        AND d.service_name = m.service_name
    WHERE m.hour >= (SELECT h - INTERVAL 25 HOUR FROM target_hour)
      AND m.hour <= (SELECT h FROM target_hour)
)
SELECT
    hour AS hour,
    service_name AS service_name,

    -- Daily billing information
    daily_total_chc AS daily_total_chc,
    daily_compute_chc AS daily_compute_chc,
    daily_storage_chc AS daily_storage_chc,
    daily_network_chc AS daily_network_chc,

    -- Estimated hourly costs
    daily_total_chc / 24 AS estimated_hourly_total_chc,
    daily_compute_chc / 24 AS estimated_hourly_compute_chc,
    daily_storage_chc / 24 AS estimated_hourly_storage_chc,
    daily_network_chc / 24 AS estimated_hourly_network_chc,

    -- Cost per CPU core
    if(allocated_cpu > 0, (daily_compute_chc / 24) / allocated_cpu, 0) AS cost_per_cpu_core_hour,

    -- Resource metrics
    allocated_cpu AS allocated_cpu,
    allocated_memory_gb AS allocated_memory_gb,
    cpu_usage_avg AS cpu_usage_avg,
    cpu_usage_p99 AS cpu_usage_p99,
    cpu_usage_max AS cpu_usage_max,
    memory_usage_pct_avg AS memory_usage_pct_avg,
    memory_usage_pct_p99 AS memory_usage_pct_p99,

    -- Efficiency metrics
    if(allocated_cpu > 0, (cpu_usage_avg / allocated_cpu) * 100, 0) AS cpu_efficiency_pct,
    memory_usage_pct_avg AS memory_efficiency_pct,
    if(allocated_cpu > 0, (((cpu_usage_avg / allocated_cpu) * 100) + memory_usage_pct_avg) / 2, 0) AS overall_efficiency_pct,

    -- Previous period values
    coalesce(prev_1h_cpu, 0) AS prev_1h_cpu_usage,
    prev_1h_daily_cost / 24 AS prev_1h_hourly_cost,
    coalesce(prev_3h_cpu, 0) AS prev_3h_cpu_usage,
    prev_3h_daily_cost / 24 AS prev_3h_hourly_cost,
    coalesce(prev_24h_cpu, 0) AS prev_24h_cpu_usage,
    prev_24h_daily_cost / 24 AS prev_24h_hourly_cost,

    -- Percent changes
    if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0) AS pct_change_1h_cpu,
    if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0) AS pct_change_1h_cost,
    if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0) AS pct_change_3h_cpu,
    if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0) AS pct_change_3h_cost,
    if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0) AS pct_change_24h_cpu,
    if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0) AS pct_change_24h_cost,

    -- Alert flags (${ALERT_THRESHOLD_PCT}% threshold)
    if(abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cpu_spike_1h,
    if(abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cpu_spike_3h,
    if(abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cpu_spike_24h,
    if(abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cost_spike_1h,
    if(abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cost_spike_3h,
    if(abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0) AS alert_cost_spike_24h,

    -- Combined alert flag
    if(
        abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= ${ALERT_THRESHOLD_PCT},
        1, 0
    ) AS alert_any

    -- ⚠️ calculated_at removed → table DEFAULT now64(3) is used

FROM metrics_with_lag
WHERE hour = (SELECT h FROM target_hour);


-- ############################################################################
-- PART 5: Regular Materialized View for Alerts
-- ############################################################################

CREATE MATERIALIZED VIEW ${DATABASE_NAME}.mv_alerts
TO ${DATABASE_NAME}.alerts
AS
SELECT
    generateUUIDv4() AS alert_id,
    now64(3) AS alert_time,
    hour,
    alert_type,
    comparison_period,
    severity,
    current_value,
    comparison_value,
    pct_change,
    ${ALERT_THRESHOLD_PCT} AS threshold_pct,
    estimated_hourly_total_chc AS estimated_hourly_chc,
    estimated_hourly_total_chc * 24 AS potential_daily_impact_chc,
    message,
    0 AS acknowledged,
    CAST(NULL AS Nullable(DateTime64(3))) AS acknowledged_at,
    service_name
FROM (
    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cpu' AS alert_type,
        '1h' AS comparison_period,
        multiIf(
            abs(pct_change_1h_cpu) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_1h_cpu) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        cpu_usage_avg AS current_value,
        prev_1h_cpu_usage AS comparison_value,
        pct_change_1h_cpu AS pct_change,
        concat(
            'CPU usage changed by ', toString(round(abs(pct_change_1h_cpu), 1)), '% ',
            if(pct_change_1h_cpu > 0, 'increase', 'decrease'),
            ' compared to 1 hour ago (from ', toString(round(prev_1h_cpu_usage, 2)), ' to ', toString(round(cpu_usage_avg, 2)), ' cores)'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cpu_spike_1h = 1

    UNION ALL

    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cpu' AS alert_type,
        '3h' AS comparison_period,
        multiIf(
            abs(pct_change_3h_cpu) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_3h_cpu) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        cpu_usage_avg AS current_value,
        prev_3h_cpu_usage AS comparison_value,
        pct_change_3h_cpu AS pct_change,
        concat(
            'CPU usage changed by ', toString(round(abs(pct_change_3h_cpu), 1)), '% ',
            if(pct_change_3h_cpu > 0, 'increase', 'decrease'),
            ' compared to 3 hours ago (from ', toString(round(prev_3h_cpu_usage, 2)), ' to ', toString(round(cpu_usage_avg, 2)), ' cores)'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cpu_spike_3h = 1

    UNION ALL

    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cpu' AS alert_type,
        '24h' AS comparison_period,
        multiIf(
            abs(pct_change_24h_cpu) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_24h_cpu) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        cpu_usage_avg AS current_value,
        prev_24h_cpu_usage AS comparison_value,
        pct_change_24h_cpu AS pct_change,
        concat(
            'CPU usage changed by ', toString(round(abs(pct_change_24h_cpu), 1)), '% ',
            if(pct_change_24h_cpu > 0, 'increase', 'decrease'),
            ' compared to 24 hours ago (from ', toString(round(prev_24h_cpu_usage, 2)), ' to ', toString(round(cpu_usage_avg, 2)), ' cores)'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cpu_spike_24h = 1

    UNION ALL

    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cost' AS alert_type,
        '1h' AS comparison_period,
        multiIf(
            abs(pct_change_1h_cost) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_1h_cost) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        estimated_hourly_total_chc AS current_value,
        prev_1h_hourly_cost AS comparison_value,
        pct_change_1h_cost AS pct_change,
        concat(
            'Hourly cost changed by ', toString(round(abs(pct_change_1h_cost), 1)), '% ',
            if(pct_change_1h_cost > 0, 'increase', 'decrease'),
            ' compared to 1 hour ago (from $', toString(round(prev_1h_hourly_cost, 4)), ' to $', toString(round(estimated_hourly_total_chc, 4)), ')'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cost_spike_1h = 1

    UNION ALL

    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cost' AS alert_type,
        '3h' AS comparison_period,
        multiIf(
            abs(pct_change_3h_cost) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_3h_cost) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        estimated_hourly_total_chc AS current_value,
        prev_3h_hourly_cost AS comparison_value,
        pct_change_3h_cost AS pct_change,
        concat(
            'Hourly cost changed by ', toString(round(abs(pct_change_3h_cost), 1)), '% ',
            if(pct_change_3h_cost > 0, 'increase', 'decrease'),
            ' compared to 3 hours ago (from $', toString(round(prev_3h_hourly_cost, 4)), ' to $', toString(round(estimated_hourly_total_chc, 4)), ')'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cost_spike_3h = 1

    UNION ALL

    SELECT
        hour,
        service_name,
        estimated_hourly_total_chc,
        'cost' AS alert_type,
        '24h' AS comparison_period,
        multiIf(
            abs(pct_change_24h_cost) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
            abs(pct_change_24h_cost) >= ${WARNING_THRESHOLD_PCT}, 'warning',
            'info'
        ) AS severity,
        estimated_hourly_total_chc AS current_value,
        prev_24h_hourly_cost AS comparison_value,
        pct_change_24h_cost AS pct_change,
        concat(
            'Hourly cost changed by ', toString(round(abs(pct_change_24h_cost), 1)), '% ',
            if(pct_change_24h_cost > 0, 'increase', 'decrease'),
            ' compared to 24 hours ago (from $', toString(round(prev_24h_hourly_cost, 4)), ' to $', toString(round(estimated_hourly_total_chc, 4)), ')'
        ) AS message
    FROM ${DATABASE_NAME}.hourly_analysis
    WHERE alert_cost_spike_24h = 1
);


-- ############################################################################
-- PART 6: Dashboard Views
-- ############################################################################

-- ----------------------------------------------------------------------------
-- View 1: Dashboard (Simplified Summary)
-- ----------------------------------------------------------------------------
CREATE VIEW ${DATABASE_NAME}.v_dashboard AS
SELECT
    hour,
    service_name,
    round(daily_total_chc, 2) AS daily_chc,
    round(estimated_hourly_total_chc, 4) AS hourly_chc,
    round(cpu_usage_avg, 4) AS cpu_cores,
    round(cpu_efficiency_pct, 1) AS cpu_eff_pct,
    round(memory_usage_pct_avg, 1) AS mem_eff_pct,
    round(pct_change_1h_cpu, 1) AS chg_1h_pct,
    round(pct_change_3h_cpu, 1) AS chg_3h_pct,
    round(pct_change_24h_cpu, 1) AS chg_24h_pct,
    alert_any,
    multiIf(
        alert_cpu_spike_24h = 1, '24h',
        alert_cpu_spike_3h = 1, '3h',
        alert_cpu_spike_1h = 1, '1h',
        alert_cost_spike_24h = 1, 'cost_24h',
        alert_cost_spike_3h = 1, 'cost_3h',
        alert_cost_spike_1h = 1, 'cost_1h',
        'none'
    ) AS alert_source
FROM ${DATABASE_NAME}.hourly_analysis
ORDER BY hour DESC
LIMIT 100;

-- ----------------------------------------------------------------------------
-- View 2: Alerts View (Most Recent Unacknowledged)
-- ----------------------------------------------------------------------------
CREATE VIEW ${DATABASE_NAME}.v_alerts AS
SELECT
    alert_id,
    alert_time,
    hour,
    alert_type,
    comparison_period,
    severity,
    round(current_value, 2) AS current_val,
    round(comparison_value, 2) AS prev_val,
    round(pct_change, 1) AS change_pct,
    round(estimated_hourly_chc, 4) AS hourly_cost,
    round(potential_daily_impact_chc, 2) AS daily_impact,
    message,
    acknowledged,
    service_name
FROM ${DATABASE_NAME}.alerts
WHERE acknowledged = 0
ORDER BY alert_time DESC, severity DESC
LIMIT 50;
