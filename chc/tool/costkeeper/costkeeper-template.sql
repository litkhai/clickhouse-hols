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
--   ${SERVICE_NAME}             - Service name (e.g., Seoul, Tokyo)
--   ${ALLOCATED_CPU}            - Allocated CPU cores (e.g., 2.0)
--   ${ALLOCATED_MEMORY}         - Allocated memory in GB (e.g., 8.0)
--   ${ALERT_THRESHOLD_PCT}      - Alert threshold percentage (e.g., 20.0)
--   ${WARNING_THRESHOLD_PCT}    - Warning threshold percentage (e.g., 30.0)
--   ${CRITICAL_THRESHOLD_PCT}   - Critical threshold percentage (e.g., 50.0)
--   ${DATA_RETENTION_DAYS}      - Data retention in days (e.g., 365)
--   ${ALERT_RETENTION_DAYS}     - Alert retention in days (e.g., 90)
--
-- ============================================================================


-- ############################################################################
-- PART 1: Cleanup Existing Objects (Safe Order)
-- ############################################################################

-- Step 1: Drop Materialized Views (dependency order)
DROP VIEW IF EXISTS ${DATABASE_NAME}.mv_alerts;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_hourly_analysis;
DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_hourly_metrics;

-- Step 2: Drop Regular Views
DROP VIEW IF EXISTS ${DATABASE_NAME}.v_dashboard;
DROP VIEW IF EXISTS ${DATABASE_NAME}.v_alerts;

-- Step 3: Backup Data (optional - uncomment if needed)
-- CREATE TABLE ${DATABASE_NAME}.hourly_analysis_backup AS SELECT * FROM ${DATABASE_NAME}.hourly_analysis;
-- CREATE TABLE ${DATABASE_NAME}.alerts_backup AS SELECT * FROM ${DATABASE_NAME}.alerts;

-- Step 4: Drop Tables (Warning: Data loss!)
DROP TABLE IF EXISTS ${DATABASE_NAME}.hourly_analysis;
DROP TABLE IF EXISTS ${DATABASE_NAME}.alerts;


-- ############################################################################
-- PART 2: Table Schema
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Layer 0: Daily Billing (Cloud API Data) - Keep Existing
-- ----------------------------------------------------------------------------
-- ${DATABASE_NAME}.daily_billing table is preserved
-- ${DATABASE_NAME}.rmv_daily_billing (RMV) is preserved

-- ----------------------------------------------------------------------------
-- Layer 1: Hourly Metrics - Keep Existing
-- ----------------------------------------------------------------------------
-- ${DATABASE_NAME}.hourly_metrics table is preserved
-- ${DATABASE_NAME}.rmv_hourly_metrics will be recreated below

-- ----------------------------------------------------------------------------
-- Layer 2: Hourly Analysis (Main Analysis Table)
-- ----------------------------------------------------------------------------
CREATE TABLE ${DATABASE_NAME}.hourly_analysis
(
    -- Time information
    hour DateTime,
    service_name String DEFAULT '${SERVICE_NAME}',

    -- Daily cost information (from daily_billing)
    daily_total_chc Float64,
    daily_compute_chc Float64,
    daily_storage_chc Float64,
    daily_network_chc Float64,

    -- Hourly estimated cost (simple /24 distribution)
    estimated_hourly_total_chc Float64,
    estimated_hourly_compute_chc Float64,
    estimated_hourly_storage_chc Float64,
    estimated_hourly_network_chc Float64,

    -- Cost per CPU core
    cost_per_cpu_core_hour Float64,

    -- Resource allocation
    allocated_cpu Float64,
    allocated_memory_gb Float64,

    -- Current hour resource usage
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
    -- Change rate (%)
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
    alert_any UInt8,

    -- Metadata
    calculated_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = SharedReplacingMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}', calculated_at)
ORDER BY (hour, service_name)
TTL hour + INTERVAL ${DATA_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;

-- ----------------------------------------------------------------------------
-- Layer 3: Alerts (Alert Storage)
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

    -- Status management (for external system integration)
    acknowledged UInt8 DEFAULT 0,
    acknowledged_at Nullable(DateTime64(3)),

    -- Service information
    service_name String DEFAULT '${SERVICE_NAME}'
)
ENGINE = SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')
ORDER BY (alert_time, hour, alert_type, comparison_period)
TTL alert_time + INTERVAL ${ALERT_RETENTION_DAYS} DAY
SETTINGS index_granularity = 8192;


-- ############################################################################
-- PART 3: Refreshable Materialized View - Hourly Metrics
-- ############################################################################

DROP VIEW IF EXISTS ${DATABASE_NAME}.rmv_hourly_metrics;

CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_hourly_metrics
REFRESH EVERY 1 HOUR
TO ${DATABASE_NAME}.hourly_metrics
AS
WITH
    target_hour AS (
        SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
    ),
    metrics_agg AS (
        SELECT
            (SELECT h FROM target_hour) as hour,

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

            -- Memory metrics
            (avgIf(value, metric = 'OSMemoryTotal') - avgIf(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_avg_gb,
            (quantileIf(0.99)(value, metric = 'OSMemoryTotal') - quantileIf(0.99)(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_p99_gb,
            (maxIf(value, metric = 'OSMemoryTotal') - minIf(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_max_gb,

            ((avgIf(value, metric = 'OSMemoryTotal') - avgIf(value, metric = 'OSMemoryAvailable')) / avgIf(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_avg,
            ((quantileIf(0.99)(value, metric = 'OSMemoryTotal') - quantileIf(0.99)(value, metric = 'OSMemoryAvailable')) / quantileIf(0.99)(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_p99,
            ((maxIf(value, metric = 'OSMemoryTotal') - minIf(value, metric = 'OSMemoryAvailable')) / maxIf(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_max,

            -- Disk metrics
            sumIf(value, metric LIKE 'OSReadBytes%') as disk_read_bytes,
            sumIf(value, metric LIKE 'OSWriteBytes%') as disk_write_bytes,
            maxIf(value, metric = 'FilesystemMainPathTotalBytes') / (1024 * 1024 * 1024) as disk_total_gb,
            maxIf(value, metric = 'FilesystemMainPathUsedBytes') / (1024 * 1024 * 1024) as disk_used_gb,
            (maxIf(value, metric = 'FilesystemMainPathUsedBytes') / maxIf(value, metric = 'FilesystemMainPathTotalBytes')) * 100 as disk_usage_pct,

            -- Network metrics
            sumIf(value, metric LIKE 'OSNetworkReceiveBytes%') as network_rx_bytes,
            sumIf(value, metric LIKE 'OSNetworkTransmitBytes%') as network_tx_bytes,

            -- Load Average
            avgIf(value, metric = 'LoadAverage1') as load_avg_1m,
            avgIf(value, metric = 'LoadAverage5') as load_avg_5m,
            avgIf(value, metric = 'OSProcessesRunning') as processes_running_avg
        FROM system.asynchronous_metric_log
        WHERE event_time >= (SELECT h FROM target_hour)
          AND event_time < (SELECT h + INTERVAL 1 HOUR FROM target_hour)
    )
SELECT
    hour,
    ${ALLOCATED_CPU} as allocated_cpu,
    ${ALLOCATED_MEMORY} as allocated_memory_gb,
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
    '${SERVICE_NAME}' as service_name,
    now64(3) as collected_at
FROM metrics_agg;


-- ############################################################################
-- PART 4: Refreshable Materialized View - Hourly Analysis
-- ############################################################################

CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_hourly_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
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
    ) AS alert_any,

    now64(3) AS calculated_at

FROM metrics_with_lag
WHERE hour = (SELECT h FROM target_hour);


-- ############################################################################
-- PART 5: Alert Auto-generation Materialized View
-- ############################################################################

CREATE MATERIALIZED VIEW ${DATABASE_NAME}.mv_alerts
TO ${DATABASE_NAME}.alerts
AS
SELECT
    generateUUIDv4() AS alert_id,
    now64(3) AS alert_time,
    hour AS hour,

    -- Determine alert type
    multiIf(
        alert_cpu_spike_1h = 1 OR alert_cpu_spike_3h = 1 OR alert_cpu_spike_24h = 1, 'cpu',
        alert_cost_spike_1h = 1 OR alert_cost_spike_3h = 1 OR alert_cost_spike_24h = 1, 'cost',
        'unknown'
    ) AS alert_type,

    -- Determine comparison period
    multiIf(
        alert_cpu_spike_24h = 1 OR alert_cost_spike_24h = 1, '24h',
        alert_cpu_spike_3h = 1 OR alert_cost_spike_3h = 1, '3h',
        alert_cpu_spike_1h = 1 OR alert_cost_spike_1h = 1, '1h',
        'unknown'
    ) AS comparison_period,

    -- Determine severity
    multiIf(
        greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu),
                 abs(pct_change_1h_cost), abs(pct_change_3h_cost), abs(pct_change_24h_cost)) >= ${CRITICAL_THRESHOLD_PCT}, 'critical',
        greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu),
                 abs(pct_change_1h_cost), abs(pct_change_3h_cost), abs(pct_change_24h_cost)) >= ${WARNING_THRESHOLD_PCT}, 'warning',
        'info'
    ) AS severity,

    -- Current value
    cpu_usage_avg AS current_value,

    -- Comparison value (period with largest change)
    multiIf(
        abs(pct_change_24h_cpu) >= abs(pct_change_3h_cpu) AND abs(pct_change_24h_cpu) >= abs(pct_change_1h_cpu), prev_24h_cpu_usage,
        abs(pct_change_3h_cpu) >= abs(pct_change_1h_cpu), prev_3h_cpu_usage,
        prev_1h_cpu_usage
    ) AS comparison_value,

    -- Change rate (largest value)
    greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu)) AS pct_change,

    ${ALERT_THRESHOLD_PCT} AS threshold_pct,
    estimated_hourly_total_chc AS estimated_hourly_chc,
    estimated_hourly_total_chc * 24 AS potential_daily_impact_chc,

    -- Generate alert message
    concat(
        '[', service_name, '] ',
        multiIf(
            greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu)) >= ${CRITICAL_THRESHOLD_PCT}, '🔴 CRITICAL',
            greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu)) >= ${WARNING_THRESHOLD_PCT}, '🟠 WARNING',
            '🟡 INFO'
        ),
        ' | CPU: ', toString(round(cpu_usage_avg, 4)), ' cores',
        ' | Change: ',
        multiIf(
            abs(pct_change_24h_cpu) >= abs(pct_change_3h_cpu) AND abs(pct_change_24h_cpu) >= abs(pct_change_1h_cpu),
            concat('24h ago: ', toString(round(pct_change_24h_cpu, 1)), '%'),
            abs(pct_change_3h_cpu) >= abs(pct_change_1h_cpu),
            concat('3h ago: ', toString(round(pct_change_3h_cpu, 1)), '%'),
            concat('1h ago: ', toString(round(pct_change_1h_cpu, 1)), '%')
        ),
        ' | Est. Cost: $', toString(round(estimated_hourly_total_chc * 24, 2)), '/day'
    ) AS message,

    toUInt8(0) AS acknowledged,
    toNullable(toDateTime64('1970-01-01 00:00:00', 3)) AS acknowledged_at,
    service_name AS service_name
FROM ${DATABASE_NAME}.hourly_analysis
WHERE alert_any = 1;


-- ############################################################################
-- PART 6: Convenience Views
-- ############################################################################

-- Dashboard View
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
        '-'
    ) AS alert_trigger
FROM ${DATABASE_NAME}.hourly_analysis
ORDER BY hour DESC;

-- Recent Alerts View
CREATE VIEW ${DATABASE_NAME}.v_alerts AS
SELECT
    alert_time,
    hour,
    severity,
    alert_type,
    comparison_period,
    round(current_value, 4) AS current_val,
    round(comparison_value, 4) AS compare_val,
    round(pct_change, 1) AS change_pct,
    round(potential_daily_impact_chc, 2) AS daily_impact_chc,
    message,
    acknowledged
FROM ${DATABASE_NAME}.alerts
ORDER BY alert_time DESC
LIMIT 100;


-- ############################################################################
-- PART 7: Initial Data Load (Based on Existing Data)
-- ############################################################################

-- Warning: Only execute if hourly_metrics already has data
-- If no data exists, skip this and let RMV auto-populate

INSERT INTO ${DATABASE_NAME}.hourly_analysis
WITH
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

        coalesce(d.total_chc, 0) AS daily_total_chc,
        coalesce(d.compute_chc, 0) AS daily_compute_chc,
        coalesce(d.storage_chc, 0) AS daily_storage_chc,
        coalesce(d.network_chc, 0) AS daily_network_chc,

        lagInFrame(m.cpu_usage_avg, 1) OVER w AS prev_1h_cpu,
        lagInFrame(m.cpu_usage_avg, 3) OVER w AS prev_3h_cpu,
        lagInFrame(m.cpu_usage_avg, 24) OVER w AS prev_24h_cpu,
        lagInFrame(coalesce(d.total_chc, 0), 1) OVER w AS prev_1h_daily_cost,
        lagInFrame(coalesce(d.total_chc, 0), 3) OVER w AS prev_3h_daily_cost,
        lagInFrame(coalesce(d.total_chc, 0), 24) OVER w AS prev_24h_daily_cost

    FROM ${DATABASE_NAME}.hourly_metrics AS m
    LEFT JOIN ${DATABASE_NAME}.daily_billing AS d
        ON toDate(m.hour) = d.date
        AND d.service_name = m.service_name
    WINDOW w AS (PARTITION BY m.service_name ORDER BY m.hour ASC)
)
SELECT
    hour AS hour,
    service_name AS service_name,

    daily_total_chc,
    daily_compute_chc,
    daily_storage_chc,
    daily_network_chc,

    daily_total_chc / 24,
    daily_compute_chc / 24,
    daily_storage_chc / 24,
    daily_network_chc / 24,

    if(allocated_cpu > 0, (daily_compute_chc / 24) / allocated_cpu, 0),

    allocated_cpu,
    allocated_memory_gb,
    cpu_usage_avg,
    cpu_usage_p99,
    cpu_usage_max,
    memory_usage_pct_avg,
    memory_usage_pct_p99,

    if(allocated_cpu > 0, (cpu_usage_avg / allocated_cpu) * 100, 0),
    memory_usage_pct_avg,
    if(allocated_cpu > 0, ((cpu_usage_avg / allocated_cpu) * 100 + memory_usage_pct_avg) / 2, 0),

    coalesce(prev_1h_cpu, 0),
    coalesce(prev_1h_daily_cost, 0) / 24,
    coalesce(prev_3h_cpu, 0),
    coalesce(prev_3h_daily_cost, 0) / 24,
    coalesce(prev_24h_cpu, 0),
    coalesce(prev_24h_daily_cost, 0) / 24,

    if(coalesce(prev_1h_cpu, 0) > 0, (cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu * 100, 0),
    if(coalesce(prev_1h_daily_cost, 0) > 0, (daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost * 100, 0),
    if(coalesce(prev_3h_cpu, 0) > 0, (cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu * 100, 0),
    if(coalesce(prev_3h_daily_cost, 0) > 0, (daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost * 100, 0),
    if(coalesce(prev_24h_cpu, 0) > 0, (cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu * 100, 0),
    if(coalesce(prev_24h_daily_cost, 0) > 0, (daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost * 100, 0),

    if(abs(if(coalesce(prev_1h_cpu, 0) > 0, (cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),
    if(abs(if(coalesce(prev_3h_cpu, 0) > 0, (cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),
    if(abs(if(coalesce(prev_24h_cpu, 0) > 0, (cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),
    if(abs(if(coalesce(prev_1h_daily_cost, 0) > 0, (daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),
    if(abs(if(coalesce(prev_3h_daily_cost, 0) > 0, (daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),
    if(abs(if(coalesce(prev_24h_daily_cost, 0) > 0, (daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT}, 1, 0),

    if(
        abs(if(coalesce(prev_1h_cpu, 0) > 0, (cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(coalesce(prev_3h_cpu, 0) > 0, (cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(coalesce(prev_24h_cpu, 0) > 0, (cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(coalesce(prev_1h_daily_cost, 0) > 0, (daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(coalesce(prev_3h_daily_cost, 0) > 0, (daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT} OR
        abs(if(coalesce(prev_24h_daily_cost, 0) > 0, (daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost * 100, 0)) >= ${ALERT_THRESHOLD_PCT},
        1, 0
    ),

    now64(3)
FROM metrics_with_lag;


-- ############################################################################
-- PART 8: Verification Queries
-- ############################################################################

-- Check Dashboard
SELECT * FROM ${DATABASE_NAME}.v_dashboard LIMIT 10;

-- Check Alerts
SELECT * FROM ${DATABASE_NAME}.v_alerts LIMIT 10;

-- Check RMV Status
SELECT
    database,
    view,
    status,
    last_success_time,
    next_refresh_time,
    if(exception = '', '✅ OK', concat('❌ ', exception)) as health_status
FROM system.view_refreshes
WHERE database = '${DATABASE_NAME}'
ORDER BY view;

-- Check Row Counts
SELECT
    'hourly_metrics' as table_name,
    count(*) as total_rows,
    min(hour) as earliest_hour,
    max(hour) as latest_hour
FROM ${DATABASE_NAME}.hourly_metrics
UNION ALL
SELECT
    'hourly_analysis' as table_name,
    count(*) as total_rows,
    min(hour) as earliest_hour,
    max(hour) as latest_hour
FROM ${DATABASE_NAME}.hourly_analysis
UNION ALL
SELECT
    'alerts' as table_name,
    count(*) as total_rows,
    min(hour) as earliest_hour,
    max(hour) as latest_hour
FROM ${DATABASE_NAME}.alerts;

-- List All Objects
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) as size
FROM system.tables
WHERE database = '${DATABASE_NAME}'
ORDER BY engine, name;
