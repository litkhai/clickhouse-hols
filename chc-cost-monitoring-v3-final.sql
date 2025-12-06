-- ============================================================================
-- ClickHouse Cloud Cost Monitoring & Alerting System v3 (Final)
-- ============================================================================
-- 업데이트: 2025-12-06
-- 주요 변경사항:
--   - unused_cpu_cores, unused_compute_cost_hourly 컬럼 제거
--   - 효율성 분석에 집중 (낭비 비용 계산 제거)
--   - 비교 기준: 1h, 3h, 24h 전 (단순 lag)
-- ============================================================================

-- ############################################################################
-- PART 1: 기존 객체 정리
-- ############################################################################

-- ⚠️ 주의: 데이터 손실 방지를 위해 백업 먼저 수행 권장
-- CREATE TABLE billing_monitoring.hourly_cost_analysis_backup AS 
--   SELECT * FROM billing_monitoring.hourly_cost_analysis;

DROP VIEW IF EXISTS billing_monitoring.mv_cost_alerts;
DROP VIEW IF EXISTS billing_monitoring.rmv_hourly_cost_analysis;
DROP VIEW IF EXISTS billing_monitoring.v_dashboard;
DROP VIEW IF EXISTS billing_monitoring.v_recent_alerts;

DROP TABLE IF EXISTS billing_monitoring.hourly_cost_analysis;
DROP TABLE IF EXISTS billing_monitoring.cost_alerts;


-- ############################################################################
-- PART 2: 테이블 스키마
-- ############################################################################

-- ----------------------------------------------------------------------------
-- Layer 2: Hourly Cost Analysis (비용-리소스 통합)
-- ----------------------------------------------------------------------------
CREATE TABLE billing_monitoring.hourly_cost_analysis (
    hour DateTime,
    service_name String DEFAULT 'production',
    
    -- 비용 정보 (Billing API 원본)
    daily_total_chc Float64,
    daily_compute_chc Float64,
    daily_storage_chc Float64,
    daily_network_chc Float64,
    
    -- 시간별 추정 비용 (균등 분배)
    estimated_hourly_total_chc Float64,
    estimated_hourly_compute_chc Float64,
    estimated_hourly_storage_chc Float64,
    estimated_hourly_network_chc Float64,
    cost_per_cpu_core_hour Float64,
    
    -- 리소스 할당 및 사용량
    allocated_cpu Float64,
    allocated_memory_gb Float64,
    cpu_usage_avg Float64,
    cpu_usage_p99 Float64,
    cpu_usage_max Float64,
    memory_usage_pct_avg Float64,
    memory_usage_pct_p99 Float64,
    
    -- 효율성 지표
    cpu_efficiency_pct Float64,
    memory_efficiency_pct Float64,
    overall_efficiency_pct Float64,
    
    -- 비교 기준 (lagInFrame)
    prev_1h_cpu_usage Float64,
    prev_1h_hourly_cost Float64,
    prev_3h_cpu_usage Float64,
    prev_3h_hourly_cost Float64,
    prev_24h_cpu_usage Float64,
    prev_24h_hourly_cost Float64,
    
    -- 변화율
    pct_change_1h_cpu Float64,
    pct_change_1h_cost Float64,
    pct_change_3h_cpu Float64,
    pct_change_3h_cost Float64,
    pct_change_24h_cpu Float64,
    pct_change_24h_cost Float64,
    
    -- Alert 플래그 (20% 임계값)
    alert_cpu_spike_1h UInt8,
    alert_cpu_spike_3h UInt8,
    alert_cpu_spike_24h UInt8,
    alert_cost_spike_1h UInt8,
    alert_cost_spike_3h UInt8,
    alert_cost_spike_24h UInt8,
    alert_any UInt8,
    
    calculated_at DateTime64(3) DEFAULT now64(3)
) ENGINE = SharedReplacingMergeTree(calculated_at)
ORDER BY (hour, service_name)
TTL hour + INTERVAL 365 DAY;

-- ----------------------------------------------------------------------------
-- Layer 3: Cost Alerts
-- ----------------------------------------------------------------------------
CREATE TABLE billing_monitoring.cost_alerts (
    alert_id UUID DEFAULT generateUUIDv4(),
    alert_time DateTime64(3) DEFAULT now64(3),
    hour DateTime,
    
    -- Alert 분류
    alert_type LowCardinality(String),        -- 'cpu', 'cost'
    comparison_period LowCardinality(String), -- '1h', '3h', '24h'
    severity LowCardinality(String),          -- 'info', 'warning', 'critical'
    
    -- 값 정보
    current_value Float64,
    comparison_value Float64,
    pct_change Float64,
    threshold_pct Float64 DEFAULT 20.0,
    
    -- 비용 영향
    estimated_hourly_chc Float64,
    potential_daily_impact_chc Float64,
    
    -- Alert 메시지
    message String,
    
    -- 상태 관리
    acknowledged UInt8 DEFAULT 0,
    acknowledged_at Nullable(DateTime64(3)),
    
    service_name String DEFAULT 'production'
) ENGINE = SharedMergeTree
ORDER BY (alert_time, hour, alert_type, comparison_period)
TTL alert_time + INTERVAL 90 DAY;


-- ############################################################################
-- PART 3: Refreshable Materialized View - Cost Analysis
-- ############################################################################

CREATE MATERIALIZED VIEW billing_monitoring.rmv_hourly_cost_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
TO billing_monitoring.hourly_cost_analysis
AS
WITH 
target_hour AS (
    SELECT toStartOfHour(now() - INTERVAL 1 HOUR) AS h
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
        
        -- Billing 정보 조인
        coalesce(d.total_chc, 0) AS daily_total_chc,
        coalesce(d.compute_chc, 0) AS daily_compute_chc,
        coalesce(d.storage_chc, 0) AS daily_storage_chc,
        coalesce(d.network_chc, 0) AS daily_network_chc,
        
        -- lagInFrame으로 이전 값 비교 (Self JOIN 불필요)
        lagInFrame(r.cpu_usage_avg, 1) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_1h_cpu,
        
        lagInFrame(r.cpu_usage_avg, 3) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_3h_cpu,
        
        lagInFrame(r.cpu_usage_avg, 24) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_24h_cpu,
        
        lagInFrame(coalesce(d.total_chc, 0), 1) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_1h_daily_cost,
        
        lagInFrame(coalesce(d.total_chc, 0), 3) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_3h_daily_cost,
        
        lagInFrame(coalesce(d.total_chc, 0), 24) OVER (
            PARTITION BY r.service_name 
            ORDER BY r.hour ASC
        ) AS prev_24h_daily_cost
        
    FROM billing_monitoring.hourly_raw_metrics AS r
    LEFT JOIN billing_monitoring.daily_billing AS d 
        ON toDate(r.hour) = d.date 
        AND d.service_name = r.service_name
    WHERE r.hour >= (SELECT h - INTERVAL 25 HOUR FROM target_hour)
      AND r.hour <= (SELECT h FROM target_hour)
)
SELECT 
    hour,
    service_name,
    
    -- 비용 정보
    daily_total_chc,
    daily_compute_chc,
    daily_storage_chc,
    daily_network_chc,
    daily_total_chc / 24 AS estimated_hourly_total_chc,
    daily_compute_chc / 24 AS estimated_hourly_compute_chc,
    daily_storage_chc / 24 AS estimated_hourly_storage_chc,
    daily_network_chc / 24 AS estimated_hourly_network_chc,
    if(allocated_cpu > 0, (daily_compute_chc / 24) / allocated_cpu, 0) AS cost_per_cpu_core_hour,
    
    -- 리소스 사용량
    allocated_cpu,
    allocated_memory_gb,
    cpu_usage_avg,
    cpu_usage_p99,
    cpu_usage_max,
    memory_usage_pct_avg,
    memory_usage_pct_p99,
    
    -- 효율성 지표
    if(allocated_cpu > 0, (cpu_usage_avg / allocated_cpu) * 100, 0) AS cpu_efficiency_pct,
    memory_usage_pct_avg AS memory_efficiency_pct,
    if(allocated_cpu > 0, 
       (((cpu_usage_avg / allocated_cpu) * 100) + memory_usage_pct_avg) / 2, 
       0) AS overall_efficiency_pct,
    
    -- 비교 기준값
    coalesce(prev_1h_cpu, 0) AS prev_1h_cpu_usage,
    prev_1h_daily_cost / 24 AS prev_1h_hourly_cost,
    coalesce(prev_3h_cpu, 0) AS prev_3h_cpu_usage,
    prev_3h_daily_cost / 24 AS prev_3h_hourly_cost,
    coalesce(prev_24h_cpu, 0) AS prev_24h_cpu_usage,
    prev_24h_daily_cost / 24 AS prev_24h_hourly_cost,
    
    -- 변화율
    if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0) AS pct_change_1h_cpu,
    if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0) AS pct_change_1h_cost,
    if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0) AS pct_change_3h_cpu,
    if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0) AS pct_change_3h_cost,
    if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0) AS pct_change_24h_cpu,
    if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0) AS pct_change_24h_cost,
    
    -- Alert 플래그
    if(abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= 20, 1, 0) AS alert_cpu_spike_1h,
    if(abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= 20, 1, 0) AS alert_cpu_spike_3h,
    if(abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= 20, 1, 0) AS alert_cpu_spike_24h,
    if(abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= 20, 1, 0) AS alert_cost_spike_1h,
    if(abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= 20, 1, 0) AS alert_cost_spike_3h,
    if(abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= 20, 1, 0) AS alert_cost_spike_24h,
    
    -- 종합 Alert
    if(
        abs(if(prev_1h_cpu > 0, ((cpu_usage_avg - prev_1h_cpu) / prev_1h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_3h_cpu > 0, ((cpu_usage_avg - prev_3h_cpu) / prev_3h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_24h_cpu > 0, ((cpu_usage_avg - prev_24h_cpu) / prev_24h_cpu) * 100, 0)) >= 20 OR
        abs(if(prev_1h_daily_cost > 0, ((daily_total_chc - prev_1h_daily_cost) / prev_1h_daily_cost) * 100, 0)) >= 20 OR
        abs(if(prev_3h_daily_cost > 0, ((daily_total_chc - prev_3h_daily_cost) / prev_3h_daily_cost) * 100, 0)) >= 20 OR
        abs(if(prev_24h_daily_cost > 0, ((daily_total_chc - prev_24h_daily_cost) / prev_24h_daily_cost) * 100, 0)) >= 20,
        1, 0
    ) AS alert_any,
    
    now64(3) AS calculated_at
    
FROM metrics_with_lag
WHERE hour = (SELECT h FROM target_hour);


-- ############################################################################
-- PART 4: Alert 자동 생성 Materialized View
-- ############################################################################

CREATE MATERIALIZED VIEW billing_monitoring.mv_cost_alerts
TO billing_monitoring.cost_alerts
AS
SELECT
    generateUUIDv4() AS alert_id,
    now64(3) AS alert_time,
    hour,
    
    -- Alert 타입
    multiIf(
        alert_cpu_spike_1h = 1 OR alert_cpu_spike_3h = 1 OR alert_cpu_spike_24h = 1, 
        'cpu',
        alert_cost_spike_1h = 1 OR alert_cost_spike_3h = 1 OR alert_cost_spike_24h = 1, 
        'cost',
        'unknown'
    ) AS alert_type,
    
    -- 비교 기간
    multiIf(
        alert_cpu_spike_24h = 1 OR alert_cost_spike_24h = 1, '24h',
        alert_cpu_spike_3h = 1 OR alert_cost_spike_3h = 1, '3h',
        alert_cpu_spike_1h = 1 OR alert_cost_spike_1h = 1, '1h',
        'unknown'
    ) AS comparison_period,
    
    -- Severity
    multiIf(
        greatest(
            abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu),
            abs(pct_change_1h_cost), abs(pct_change_3h_cost), abs(pct_change_24h_cost)
        ) >= 50, 'critical',
        greatest(
            abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu),
            abs(pct_change_1h_cost), abs(pct_change_3h_cost), abs(pct_change_24h_cost)
        ) >= 30, 'warning',
        'info'
    ) AS severity,
    
    cpu_usage_avg AS current_value,
    
    -- 비교값 (가장 큰 변화 기간)
    multiIf(
        abs(pct_change_24h_cpu) >= abs(pct_change_3h_cpu) AND 
        abs(pct_change_24h_cpu) >= abs(pct_change_1h_cpu), 
        prev_24h_cpu_usage,
        abs(pct_change_3h_cpu) >= abs(pct_change_1h_cpu), 
        prev_3h_cpu_usage,
        prev_1h_cpu_usage
    ) AS comparison_value,
    
    greatest(
        abs(pct_change_1h_cpu), 
        abs(pct_change_3h_cpu), 
        abs(pct_change_24h_cpu)
    ) AS pct_change,
    
    20.0 AS threshold_pct,
    estimated_hourly_total_chc AS estimated_hourly_chc,
    estimated_hourly_total_chc * 24 AS potential_daily_impact_chc,
    
    -- Alert 메시지
    concat(
        '[', service_name, '] ',
        multiIf(
            greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu)) >= 50, 
            '🔴 CRITICAL',
            greatest(abs(pct_change_1h_cpu), abs(pct_change_3h_cpu), abs(pct_change_24h_cpu)) >= 30, 
            '🟠 WARNING',
            '🟡 INFO'
        ),
        ' | CPU: ', toString(round(cpu_usage_avg, 4)), ' cores',
        ' | 변화: ',
        multiIf(
            abs(pct_change_24h_cpu) >= abs(pct_change_3h_cpu) AND 
            abs(pct_change_24h_cpu) >= abs(pct_change_1h_cpu),
            concat('24h 전 대비 ', toString(round(pct_change_24h_cpu, 1)), '%'),
            abs(pct_change_3h_cpu) >= abs(pct_change_1h_cpu),
            concat('3h 전 대비 ', toString(round(pct_change_3h_cpu, 1)), '%'),
            concat('1h 전 대비 ', toString(round(pct_change_1h_cpu, 1)), '%')
        ),
        ' | 예상 비용: $', toString(round(estimated_hourly_total_chc * 24, 2)), '/일'
    ) AS message,
    
    toUInt8(0) AS acknowledged,
    toNullable(toDateTime64('1970-01-01 00:00:00', 3)) AS acknowledged_at,
    service_name
FROM billing_monitoring.hourly_cost_analysis
WHERE alert_any = 1;


-- ############################################################################
-- PART 5: 편의 View
-- ############################################################################

-- 대시보드용 View
CREATE VIEW billing_monitoring.v_dashboard AS
SELECT 
    hour,
    service_name,
    round(daily_total_chc, 2) AS daily_chc,
    round(estimated_hourly_total_chc, 4) AS hourly_chc,
    round(cpu_usage_avg, 4) AS cpu_cores,
    round(cpu_efficiency_pct, 1) AS cpu_eff_pct,
    round(memory_usage_pct_avg, 1) AS mem_eff_pct,
    round(overall_efficiency_pct, 1) AS total_eff_pct,
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
FROM billing_monitoring.hourly_cost_analysis
ORDER BY hour DESC;

-- 최근 Alert 조회 View
CREATE VIEW billing_monitoring.v_recent_alerts AS
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
FROM billing_monitoring.cost_alerts
ORDER BY alert_time DESC
LIMIT 100;


-- ############################################################################
-- PART 6: 검증 쿼리
-- ############################################################################

-- RMV 상태 확인
SELECT 
    view,
    status,
    last_success_time,
    next_refresh_time,
    if(exception = '', '✅ OK', concat('❌ ', exception)) as health
FROM system.view_refreshes
WHERE database = 'billing_monitoring'
ORDER BY view;

-- 데이터 수집 확인
SELECT 
    'hourly_raw_metrics' as table_name,
    count(*) as rows,
    min(hour) as earliest,
    max(hour) as latest
FROM billing_monitoring.hourly_raw_metrics

UNION ALL

SELECT 
    'hourly_cost_analysis',
    count(*),
    min(hour),
    max(hour)
FROM billing_monitoring.hourly_cost_analysis

UNION ALL

SELECT 
    'cost_alerts',
    count(*),
    min(hour),
    max(hour)
FROM billing_monitoring.cost_alerts;

-- 대시보드 확인
SELECT * FROM billing_monitoring.v_dashboard LIMIT 5;

-- Alert 확인
SELECT * FROM billing_monitoring.v_recent_alerts LIMIT 5;


-- ############################################################################
-- PART 7: 아키텍처 요약
-- ############################################################################

/*
┌─────────────────────────────────────────────────────────────┐
│         CHC Cost Monitoring System v3 (Final)               │
│         Updated: 2025-12-06                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1: Raw Data Collection                               │
│    ├─ daily_billing (Billing API, 매일 01:00)              │
│    └─ hourly_raw_metrics (System Tables, 매 1시간)         │
│                                                             │
│  Layer 2: Cost Analysis                                     │
│    └─ hourly_cost_analysis                                  │
│       ├─ 시간별 비용 분배 (daily_chc / 24)                 │
│       ├─ 효율성 계산 (usage / allocated)                   │
│       ├─ lagInFrame 비교 (1h, 3h, 24h)                     │
│       └─ Alert 플래그 (20% 임계값)                         │
│                                                             │
│  Layer 3: Alerting                                          │
│    └─ cost_alerts                                           │
│       ├─ Severity 자동 분류                                │
│       ├─ 메시지 자동 생성                                  │
│       └─ Slack 연동 가능                                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ 주요 변경사항 (v3):                                         │
│                                                             │
│ ✅ unused_cpu_cores 제거                                    │
│ ✅ unused_compute_cost_hourly 제거                          │
│ ✅ 효율성 분석에 집중                                        │
│ ✅ 비용 분배: 단순 균등 (daily / 24)                        │
│ ✅ Alert: 1h, 3h, 24h 비교만 유지                          │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Alert 조건 (20% 임계값):                                    │
│ • 1시간 전 대비 CPU/Cost >= 20% 변화                       │
│ • 3시간 전 대비 CPU/Cost >= 20% 변화                       │
│ • 24시간 전 대비 CPU/Cost >= 20% 변화                      │
│                                                             │
│ Severity:                                                   │
│ • critical: >= 50% 변화                                    │
│ • warning: 30-50% 변화                                     │
│ • info: 20-30% 변화                                        │
└─────────────────────────────────────────────────────────────┘
*/
