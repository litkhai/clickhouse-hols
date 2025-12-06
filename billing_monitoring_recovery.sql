-- ============================================
-- ClickHouse Billing Monitoring 복구 스크립트
-- 작성일: 2025-12-06
-- ============================================

-- 이 스크립트는 billing_monitoring 스키마의 RMV들을 재생성하고
-- 데이터를 백필하는 작업을 수행합니다.

-- ============================================
-- 1. RMV 재생성 (hourly_raw_metrics)
-- ============================================

-- 기존 RMV 삭제
DROP VIEW IF EXISTS billing_monitoring.rmv_hourly_raw_metrics;

-- RMV 재생성
CREATE MATERIALIZED VIEW billing_monitoring.rmv_hourly_raw_metrics
REFRESH EVERY 1 HOUR
TO billing_monitoring.hourly_raw_metrics
AS
WITH 
    target_hour AS (
        SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
    ),
    metrics_agg AS (
        SELECT 
            (SELECT h FROM target_hour) as hour,
            -- CPU 메트릭
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
            
            -- Memory 메트릭
            (avgIf(value, metric = 'OSMemoryTotal') - avgIf(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_avg_gb,
            (quantileIf(0.99)(value, metric = 'OSMemoryTotal') - quantileIf(0.99)(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_p99_gb,
            (maxIf(value, metric = 'OSMemoryTotal') - minIf(value, metric = 'OSMemoryAvailable')) / (1024 * 1024 * 1024) as memory_used_max_gb,
            
            ((avgIf(value, metric = 'OSMemoryTotal') - avgIf(value, metric = 'OSMemoryAvailable')) / avgIf(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_avg,
            ((quantileIf(0.99)(value, metric = 'OSMemoryTotal') - quantileIf(0.99)(value, metric = 'OSMemoryAvailable')) / quantileIf(0.99)(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_p99,
            ((maxIf(value, metric = 'OSMemoryTotal') - minIf(value, metric = 'OSMemoryAvailable')) / maxIf(value, metric = 'OSMemoryTotal')) * 100 as memory_usage_pct_max,
            
            -- Disk 메트릭
            sumIf(value, metric LIKE 'OSReadBytes%') as disk_read_bytes,
            sumIf(value, metric LIKE 'OSWriteBytes%') as disk_write_bytes,
            maxIf(value, metric = 'FilesystemMainPathTotalBytes') / (1024 * 1024 * 1024) as disk_total_gb,
            maxIf(value, metric = 'FilesystemMainPathUsedBytes') / (1024 * 1024 * 1024) as disk_used_gb,
            (maxIf(value, metric = 'FilesystemMainPathUsedBytes') / maxIf(value, metric = 'FilesystemMainPathTotalBytes')) * 100 as disk_usage_pct,
            
            -- Network 메트릭
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
    2.0 as allocated_cpu,
    8.0 as allocated_memory_gb,
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
    'Seoul' as service_name,
    now64(3) as collected_at
FROM metrics_agg;

-- ============================================
-- 2. RMV 재생성 (hourly_cost_analysis)
-- ============================================

-- 기존 RMV 삭제
DROP VIEW IF EXISTS billing_monitoring.rmv_hourly_cost_analysis;

-- RMV 재생성
CREATE MATERIALIZED VIEW billing_monitoring.rmv_hourly_cost_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
TO billing_monitoring.hourly_cost_analysis
AS
WITH 
    target_hour AS (
        SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
    ),
    metrics_with_lag AS (
        SELECT 
            r.hour,
            r.service_name,
            r.allocated_cpu,
            r.allocated_memory_gb,
            r.cpu_usage_avg,
            r.cpu_usage_p99,
            r.cpu_usage_max,
            r.memory_usage_pct_avg,
            r.memory_usage_pct_p99,
            
            -- billing 정보 조인
            coalesce(d.total_chc, 0) as daily_total_chc,
            coalesce(d.compute_chc, 0) as daily_compute_chc,
            coalesce(d.storage_chc, 0) as daily_storage_chc,
            coalesce(d.network_chc, 0) as daily_network_chc,
            
            -- Lag 값 계산 (1h, 3h, 24h 이전 데이터)
            lagInFrame(r.cpu_usage_avg, 1) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_1h_cpu,
            lagInFrame(r.cpu_usage_avg, 3) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_3h_cpu,
            lagInFrame(r.cpu_usage_avg, 24) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_24h_cpu,
            
            lagInFrame(coalesce(d.total_chc, 0), 1) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_1h_daily_cost,
            lagInFrame(coalesce(d.total_chc, 0), 3) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_3h_daily_cost,
            lagInFrame(coalesce(d.total_chc, 0), 24) OVER (PARTITION BY r.service_name ORDER BY r.hour ASC) as prev_24h_daily_cost
            
        FROM billing_monitoring.hourly_raw_metrics r
        LEFT JOIN billing_monitoring.daily_billing d 
            ON toDate(r.hour) = d.date 
            AND d.service_name = r.service_name
        WHERE r.hour >= (SELECT h - INTERVAL 25 HOUR FROM target_hour)
          AND r.hour <= (SELECT h FROM target_hour)
    )
SELECT 
    hour,
    service_name,
    
    -- Daily billing 정보
    daily_total_chc,
    daily_compute_chc,
    daily_storage_chc,
    daily_network_chc,
    
    -- Estimated hourly costs
    daily_total_chc / 24 as estimated_hourly_total_chc,
    daily_compute_chc / 24 as estimated_hourly_compute_chc,
    daily_storage_chc / 24 as estimated_hourly_storage_chc,
    daily_network_chc / 24 as estimated_hourly_network_chc,
    
    -- Cost per CPU core
    if(allocated_cpu > 0, (daily_compute_chc / 24) / allocated_cpu, 0) as cost_per_cpu_core_hour,
    
    -- Resource metrics
    allocated_cpu,
    allocated_memory_gb,
    cpu_usage_avg,
    cpu_usage_p99,
    cpu_usage_max,
    memory_usage_pct_avg,
    memory_usage_pct_p99,
    
    -- Efficiency metrics
    if(allocated_cpu > 0, (cpu_usage_avg / allocated_cpu) * 100, 0) as cpu_efficiency_pct,
    memory_usage_pct_avg as memory_efficiency_pct,
    if(allocated_cpu > 0, (((cpu_usage_avg / allocated_cpu) * 100) + memory_usage_pct_avg) / 2, 0) as overall_efficiency_pct,
    
    -- Waste metrics
    allocated_cpu - cpu_usage_avg as unused_cpu_cores,
    if(allocated_cpu > 0, (daily_compute_chc / 24) * (1 - (cpu_usage_avg / allocated_cpu)), 0) as unused_compute_cost_hourly,
    
    -- Previous period values
    coalesce(prev_1h_cpu, 0) as prev_1h_cpu_usage,
    prev_1h_daily_cost / 24 as prev_1h_hourly_cost,
    coalesce(prev_3h_cpu, 0) as prev_3h_cpu_usage,
    prev_3h_daily_cost / 24 as prev_3h_hourly_cost,
    coalesce(prev_24h_cpu, 0) as prev_24h_cpu_usage,
    prev_24h_daily_cost / 24 as prev_24h_hourly_cost,
    
    -- Percent changes
    if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0) as pct_change_1h_cpu,
    if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0) as pct_change_1h_cost,
    if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0) as pct_change_3h_cpu,
    if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0) as pct_change_3h_cost,
    if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0) as pct_change_24h_cpu,
    if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0) as pct_change_24h_cost,
    
    -- Alert flags (20% threshold)
    if(abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= 20, 1, 0) as alert_cpu_spike_1h,
    if(abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= 20, 1, 0) as alert_cpu_spike_3h,
    if(abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= 20, 1, 0) as alert_cpu_spike_24h,
    if(abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= 20, 1, 0) as alert_cost_spike_1h,
    if(abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= 20, 1, 0) as alert_cost_spike_3h,
    if(abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= 20, 1, 0) as alert_cost_spike_24h,
    
    -- Combined alert flag
    if(
        abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= 20 OR
        abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= 20 OR
        abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= 20,
        1, 0
    ) as alert_any,
    
    now64(3) as calculated_at
    
FROM metrics_with_lag
WHERE hour = (SELECT h FROM target_hour);

-- ============================================
-- 3. 수동 Refresh 실행
-- ============================================

-- 즉시 실행하여 데이터 채우기
SYSTEM REFRESH VIEW billing_monitoring.rmv_hourly_raw_metrics;
SYSTEM REFRESH VIEW billing_monitoring.rmv_hourly_cost_analysis;

-- ============================================
-- 4. 검증 쿼리
-- ============================================

-- RMV 상태 확인
SELECT 
    database,
    view,
    status,
    last_success_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'billing_monitoring'
ORDER BY view;

-- 데이터 개수 확인
SELECT 
    'hourly_raw_metrics' as table_name,
    count(*) as row_count,
    min(hour) as min_hour,
    max(hour) as max_hour
FROM billing_monitoring.hourly_raw_metrics
UNION ALL
SELECT 
    'hourly_cost_analysis' as table_name,
    count(*) as row_count,
    min(hour) as min_hour,
    max(hour) as max_hour
FROM billing_monitoring.hourly_cost_analysis;

-- 대시보드 뷰 확인
SELECT * FROM billing_monitoring.v_dashboard 
ORDER BY hour DESC 
LIMIT 5;
