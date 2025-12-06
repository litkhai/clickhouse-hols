# CostKeeper Multi-Service

**Version**: 2.0-multi
**Date**: 2025-12-07
**Status**: Production Ready

---

## Overview

CostKeeper Multi-Service는 단일 ClickHouse Cloud 인스턴스에서 같은 Organization 내 **여러 서비스를 동시에 모니터링**할 수 있는 솔루션입니다.

### Key Features

- ✅ **Multi-Service Monitoring**: 같은 Organization 내 최대 20개 서비스 동시 모니터링
- ✅ **remoteSecure() Integration**: ClickHouse 네이티브 원격 접속 기능 사용
- ✅ **Centralized Dashboard**: 모든 서비스의 메트릭을 한 곳에서 분석
- ✅ **Unified Billing**: Organization 전체 비용 데이터 자동 수집
- ✅ **No External Dependencies**: 순수 ClickHouse Cloud 기능만 사용

### Limitations

- ❌ **Same Organization Only**: 다른 Organization의 서비스는 지원하지 않음
- ❌ **Max ~20 Services**: RMV timeout 제한으로 인한 권장 최대 서비스 수
- ⚠️ **Performance Impact**: 서비스당 약 1-2초의 메트릭 수집 시간 추가

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Primary Service (CostKeeper 설치 위치)                              │
│ Host: primary.ap-northeast-2.aws.clickhouse.cloud                   │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ Database: costkeeper                                           │ │
│  │                                                                │ │
│  │  RMV 2: rmv_metrics_15min (EVERY 15 MIN)                      │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │ Local Service (Primary)                                 │  │ │
│  │  │   SELECT FROM system.asynchronous_metric_log            │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │ Remote Service 1 (Seoul-dev)                            │  │ │
│  │  │   SELECT FROM remoteSecure(                             │  │ │
│  │  │     'seoul-dev.clickhouse.cloud:8443',                  │  │ │
│  │  │     'system.asynchronous_metric_log',                   │  │ │
│  │  │     'default', 'password'                               │  │ │
│  │  │   )                                                     │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │ Remote Service 2 (Tokyo)                                │  │ │
│  │  │   SELECT FROM remoteSecure(...)                         │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │                                                                │ │
│  │  → UNION ALL → metrics_15min (service_name별 구분)            │ │
│  │                                                                │ │
│  │  RMV 3: rmv_hourly_metrics (EVERY 1 HOUR)                     │ │
│  │    → hourly_metrics (service_name별 집계)                      │ │
│  │                                                                │ │
│  │  RMV 4: rmv_hourly_analysis (EVERY 1 HOUR)                    │ │
│  │    → hourly_analysis (service_name별 분석)                     │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  CHC API (Organization-wide)                                        │
│    → daily_billing (모든 서비스 비용)                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Installation

### Prerequisites

1. **ClickHouse Cloud Account**
   - Organization ID 확인
   - API Key 발급 (ClickHouse Cloud Console에서)

2. **Primary Service Selection**
   - CostKeeper 데이터베이스를 설치할 서비스 선택
   - 충분한 스토리지와 CPU 권장 (메트릭 수집용)

3. **Service Credentials**
   - 모니터링할 각 서비스의 user/password
   - Read-only user 권장 (system 테이블만 조회)

4. **Python 3**
   - Setup script가 JSON 파싱에 사용

### Step-by-Step Setup

#### 1. Download CostKeeper Multi-Service

```bash
cd /path/to/clickhouse-hols/chc/tool/costkeeper-multi
```

#### 2. Run Setup Script

```bash
./setup-costkeeper-multi.sh
```

#### 3. Follow Interactive Prompts

**Step 1: Primary Service (CostKeeper 설치 위치)**
```
Primary 서비스 호스트: primary.ap-northeast-2.aws.clickhouse.cloud
Primary 서비스 비밀번호: ********
```

**Step 2: CHC API Configuration**
```
CHC Organization ID: 9142daed-a43f-455a-a112-f721d02b80af
CHC API Key ID: mMyJAi9HVaIS90Y04AMv
CHC API Key Secret: ********
```

**Step 3: Multi-Service Selection**

Setup script가 Organization의 모든 서비스를 조회합니다:

```
사용 가능한 서비스 목록:
  [1] Primary (primary.ap-northeast-2.aws.clickhouse.cloud)
  [2] Seoul-dev (seoul-dev.ap-northeast-2.aws.clickhouse.cloud)
  [3] Tokyo-prod (tokyo.ap-northeast-1.aws.clickhouse.cloud)
  [4] Singapore-staging (singapore.ap-southeast-1.aws.clickhouse.cloud)

몇 개의 서비스를 모니터링하시겠습니까? [1]: 3

모니터링할 서비스 #1 번호를 입력하세요 (1-4): 1
모니터링할 서비스 #2 번호를 입력하세요 (1-4): 2
모니터링할 서비스 #3 번호를 입력하세요 (1-4): 3
```

**Step 4: Service Credentials**

각 서비스의 인증 정보를 입력합니다:

```
서비스: Primary (primary.ap-northeast-2.aws.clickhouse.cloud)
이 서비스는 Primary 서비스입니다. 동일한 credentials를 사용합니다.

서비스: Seoul-dev (seoul-dev.ap-northeast-2.aws.clickhouse.cloud)
User [default]: default
Password: ********

서비스: Tokyo-prod (tokyo.ap-northeast-1.aws.clickhouse.cloud)
User [default]: default
Password: ********
```

**Step 5: CostKeeper Configuration**

```
Database Name [costkeeper]: costkeeper
Data Retention (days) [90]: 90
Alert Threshold (%) [50]: 50
```

#### 4. Deployment

Setup script가 자동으로 SQL을 생성하고 배포합니다:

```
지금 ClickHouse에 배포하시겠습니까? (yes/no) [yes]: yes

[SUCCESS] CostKeeper Multi-Service가 성공적으로 배포되었습니다!

모니터링 중인 서비스:
  • Primary (primary.ap-northeast-2.aws.clickhouse.cloud)
  • Seoul-dev (seoul-dev.ap-northeast-2.aws.clickhouse.cloud)
  • Tokyo-prod (tokyo.ap-northeast-1.aws.clickhouse.cloud)
```

---

## Data Collection

### 1. Billing Data (RMV 1)

**Schedule**: 매일 01:00 (1 HOUR OFFSET)

```sql
-- Organization 전체의 모든 서비스 비용 수집
SELECT date, service_id, service_name, total_chc, compute_chc, storage_chc, network_chc
FROM url('https://api.clickhouse.cloud/v1/organizations/.../usageCost')
-- ⚠️ Multi-Service: service_id filter 제거
```

### 2. System Metrics (RMV 2)

**Schedule**: 매 15분마다

```sql
WITH
    -- Service 0 (Primary - Local)
    service_0_metrics AS (
        SELECT
            'Primary' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric='CGroupMaxCPU') as allocated_cpu,
            ...
        FROM system.asynchronous_metric_log
        WHERE event_time >= now() - INTERVAL 15 MINUTE
    ),

    -- Service 1 (Seoul-dev - Remote)
    service_1_metrics AS (
        SELECT
            'Seoul-dev' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric='CGroupMaxCPU') as allocated_cpu,
            ...
        FROM remoteSecure(
            'seoul-dev.ap-northeast-2.aws.clickhouse.cloud:8443',
            'system.asynchronous_metric_log',
            'default',
            'password'
        )
        WHERE event_time >= now() - INTERVAL 15 MINUTE
    ),

    -- Service 2 (Tokyo - Remote)
    service_2_metrics AS (
        SELECT
            'Tokyo-prod' as service_name,
            ...
        FROM remoteSecure(...)
    ),

    all_metrics AS (
        SELECT * FROM service_0_metrics
        UNION ALL
        SELECT * FROM service_1_metrics
        UNION ALL
        SELECT * FROM service_2_metrics
    )
SELECT * FROM all_metrics;
```

**Key Metrics Collected:**
- CPU: allocated_cpu, cpu_usage_avg, cpu_usage_p50/p90/p99
- Memory: allocated_memory_gb, memory_used_avg/p99/max_gb, memory_usage_pct
- Disk: disk_read/write_bytes, disk_usage_pct
- Network: network_rx/tx_bytes
- Load: load_avg_1m/5m, processes_running_avg

### 3. Hourly Aggregation (RMV 3)

**Schedule**: 매시간 02분 (2 MINUTE OFFSET)

```sql
-- 각 service_name별로 15분 데이터 4개를 1시간으로 집계
SELECT
    toStartOfHour(now() - INTERVAL 1 HOUR) as hour,
    service_name,
    avg(allocated_cpu) as allocated_cpu,
    avg(cpu_usage_avg) as cpu_usage_avg,
    ...
FROM metrics_15min
WHERE collected_at >= toStartOfHour(now() - INTERVAL 1 HOUR)
  AND collected_at < toStartOfHour(now())
GROUP BY service_name
```

### 4. Analysis & Alerts (RMV 4)

**Schedule**: 매시간 05분 (5 MINUTE OFFSET)

```sql
-- service_name별로 분석 및 Alert 생성
SELECT
    m.hour,
    m.service_name,
    m.allocated_cpu,
    m.cpu_usage_avg,
    -- Billing 데이터 JOIN
    COALESCE(d.total_chc, 0) as daily_total_chc,
    (d.total_chc / 24) as estimated_hourly_total_chc,
    -- Spike Detection
    (m.cpu_usage_avg / lagInFrame(cpu_usage_avg, 1) OVER w - 1) * 100 as pct_change_1h_cpu,
    ...
FROM hourly_metrics m
LEFT JOIN daily_billing d
    ON toDate(m.hour) = d.date
    AND m.service_name = d.service_name
WINDOW w AS (PARTITION BY m.service_name ORDER BY m.hour)
```

---

## Usage

### Query Multi-Service Metrics

#### 1. View All Services (Latest Metrics)

```sql
SELECT
    service_name,
    hour,
    allocated_cpu,
    cpu_usage_avg,
    (cpu_usage_avg / allocated_cpu) * 100 as cpu_utilization_pct,
    memory_used_avg_gb,
    memory_usage_pct_avg,
    estimated_hourly_total_chc
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
ORDER BY hour DESC, service_name;
```

#### 2. Compare Services (CPU Utilization)

```sql
SELECT
    service_name,
    avg(cpu_usage_avg) as avg_cpu_usage,
    avg((cpu_usage_avg / allocated_cpu) * 100) as avg_cpu_utilization_pct,
    sum(estimated_hourly_total_chc) as total_cost_24h
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
GROUP BY service_name
ORDER BY avg_cpu_utilization_pct DESC;
```

**Example Output:**
```
┌─service_name─┬─avg_cpu_usage─┬─avg_cpu_utilization_pct─┬─total_cost_24h─┐
│ Tokyo-prod   │          7.85 │                   78.50 │          12.45 │
│ Seoul-dev    │          3.21 │                   64.20 │           5.67 │
│ Primary      │          1.45 │                   29.00 │           4.32 │
└──────────────┴───────────────┴─────────────────────────┴────────────────┘
```

#### 3. Detect Underutilized Services

```sql
SELECT
    service_name,
    avg(allocated_cpu) as allocated_cpu,
    avg(cpu_usage_avg) as avg_cpu_usage,
    avg((cpu_usage_avg / allocated_cpu) * 100) as avg_utilization_pct,
    sum(estimated_hourly_total_chc) as total_cost_24h,
    -- Potential savings if downsized
    sum(estimated_hourly_total_chc) * 0.5 as potential_savings_50pct
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
GROUP BY service_name
HAVING avg_utilization_pct < 30  -- Less than 30% utilized
ORDER BY total_cost_24h DESC;
```

#### 4. Service-Level Alerts

```sql
SELECT
    service_name,
    hour,
    alert_type,
    comparison_period,
    current_value,
    pct_change,
    estimated_hourly_chc,
    message
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
  AND alert_any = 1
ORDER BY hour DESC, service_name;
```

#### 5. Cross-Service Cost Breakdown

```sql
SELECT
    toDate(hour) as date,
    service_name,
    sum(estimated_hourly_total_chc) as daily_cost,
    sum(estimated_hourly_compute_chc) as compute_cost,
    sum(estimated_hourly_storage_chc) as storage_cost,
    sum(estimated_hourly_network_chc) as network_cost
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 7 DAY
GROUP BY date, service_name
ORDER BY date DESC, daily_cost DESC;
```

---

## Performance Considerations

### RMV Execution Time

| Services | Local Query | Remote Queries | Total Time | Status |
|----------|-------------|----------------|------------|--------|
| 1 (single) | ~0.5s | - | ~1s | ✅ Fast |
| 3 | ~0.5s | ~2-4s | ~3-5s | ✅ Good |
| 5 | ~0.5s | ~4-8s | ~5-9s | ✅ Good |
| 10 | ~0.5s | ~10-20s | ~11-21s | ⚠️ Acceptable |
| 20 | ~0.5s | ~20-40s | ~21-41s | ⚠️ Max Recommended |
| >20 | ~0.5s | >40s | >41s | ❌ Risk of Timeout |

**RMV Default Timeout**: 10 minutes (600 seconds)

### Network Traffic

**Per 15-minute collection:**
- Local service: ~0 (no network)
- Remote service: ~10-50KB (system.asynchronous_metric_log)

**Example (5 services):**
- Per collection: ~40-200KB
- Per hour: 4 collections × ~40-200KB = ~160KB-800KB
- Per day: 96 collections × ~40-200KB = ~4-20MB

**Conclusion**: Network traffic is negligible for up to 20 services.

### Recommendations

1. **Optimal Service Count**: 5-10 services
2. **Monitor RMV Status**:
   ```sql
   SELECT view, status, last_success_time, exception
   FROM system.view_refreshes
   WHERE database = 'costkeeper'
     AND view = 'rmv_metrics_15min';
   ```
3. **Check Execution Time**:
   ```sql
   SELECT
       toStartOfFifteenMinutes(event_time) as period,
       query_duration_ms / 1000 as duration_seconds
   FROM system.query_log
   WHERE query LIKE '%rmv_metrics_15min%'
     AND type = 'QueryFinish'
   ORDER BY event_time DESC
   LIMIT 10;
   ```

---

## Security

### Credential Management

**⚠️ IMPORTANT**: All service credentials are stored in `.credentials` file.

```bash
# File location
chc/tool/costkeeper-multi/.credentials

# File permissions (automatically set by setup script)
-rw------- 1 user user  .credentials  # 600 (owner read/write only)
```

**Security Risks:**
- ✅ TLS encryption via remoteSecure() (port 8443)
- ⚠️ Primary service compromise = access to all services
- ⚠️ Credentials stored in plain text

**Mitigation:**
1. **Use Read-Only User**:
   ```sql
   -- On each monitored service
   CREATE USER costkeeper_readonly IDENTIFIED BY 'secure_password';
   GRANT SELECT ON system.* TO costkeeper_readonly;
   ```

2. **Restrict File Access**:
   ```bash
   chmod 600 .credentials
   chown your_user:your_user .credentials
   ```

3. **Network Isolation**:
   - ClickHouse Cloud uses private network between regions
   - TLS encryption for all connections

---

## Migration from Single-Service

If you have an existing single-service CostKeeper installation:

### Option 1: Fresh Multi-Service Install

```bash
# Backup existing installation
cp -r costkeeper costkeeper-backup

# Install multi-service version
cd costkeeper-multi
./setup-costkeeper-multi.sh
```

### Option 2: Migrate Data (Optional)

```sql
-- On new multi-service instance, insert historical data from old single-service
INSERT INTO costkeeper.hourly_analysis
SELECT
    hour,
    allocated_cpu,
    allocated_memory_gb,
    ...,
    'OldServiceName' as service_name  -- Add service_name column
FROM old_costkeeper.hourly_analysis;
```

---

## Troubleshooting

### 1. Remote Service Connection Failed

**Error:**
```
[ERROR] 원격 서비스 연결 실패. 인증 정보를 확인해주세요.
Code: 516. DB::Exception: default: Authentication failed
```

**Solution:**
- Verify username/password for remote service
- Check if user has SELECT permission on system.asynchronous_metric_log
- Ensure remote service is running (check CHC Console)

### 2. RMV Taking Too Long

**Symptoms:**
```sql
SELECT view, status, last_success_time, exception
FROM system.view_refreshes
WHERE database = 'costkeeper' AND view = 'rmv_metrics_15min';

-- status: Running (for >5 minutes)
```

**Solution:**
- Reduce number of monitored services
- Check network latency between services:
  ```sql
  SELECT remoteSecure(
      'service.clickhouse.cloud:8443',
      'system.one',
      'user', 'password'
  );  -- Should return quickly
  ```

### 3. Missing Data for Some Services

**Symptoms:**
```sql
SELECT service_name, count(*) as metric_count
FROM costkeeper.metrics_15min
WHERE collected_at >= now() - INTERVAL 1 HOUR
GROUP BY service_name;

-- Some services have 0 rows
```

**Solution:**
- Check if service is running (CHC Console)
- Verify credentials in `.credentials` file
- Check RMV exception:
  ```sql
  SELECT exception FROM system.view_refreshes
  WHERE database = 'costkeeper' AND view = 'rmv_metrics_15min';
  ```

### 4. Service Name Mismatch with Billing

**Symptoms:**
```sql
-- hourly_analysis shows NULL for daily_total_chc
SELECT service_name, daily_total_chc
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
  AND daily_total_chc = 0;
```

**Solution:**
- Service names must match between:
  1. Setup script input (user-defined name)
  2. CHC API entityName (from usageCost endpoint)
- Check actual billing service names:
  ```sql
  SELECT DISTINCT service_name
  FROM costkeeper.daily_billing
  ORDER BY service_name;
  ```
- Update metrics with correct names if needed:
  ```sql
  -- If service names don't match, update metrics_15min
  ALTER TABLE costkeeper.metrics_15min
  UPDATE service_name = 'CorrectName'
  WHERE service_name = 'WrongName';
  ```

---

## FAQ

### Q1: Can I monitor services in different Organizations?

**A**: No. CostKeeper Multi-Service는 같은 Organization 내 서비스만 지원합니다.

**Reason**: CHC API는 Organization 단위로 동작하며, 다른 Organization은 별도 API key가 필요합니다.

### Q2: What happens if one service is down?

**A**: remoteSecure() will timeout for that service, but other services will continue to collect data.

RMV 2 will log an exception:
```sql
SELECT exception FROM system.view_refreshes
WHERE database = 'costkeeper' AND view = 'rmv_metrics_15min';

-- "DB::NetException: Connection refused (service.clickhouse.cloud:8443)"
```

The failed service will have missing data for that 15-minute period.

### Q3: Can I add/remove services without reinstalling?

**A**: Currently, no. You need to re-run the setup script.

**Workaround** (Advanced):
1. Edit `.credentials` file manually
2. Regenerate SQL with updated service list
3. Drop and recreate `rmv_metrics_15min`

**Future Enhancement**: Dynamic service management without RMV recreation.

### Q4: How much does multi-service monitoring cost?

**Estimated Cost (per month):**
- Primary service storage: ~500MB-2GB (depending on service count and retention)
- Network traffic: ~100MB-500MB (15-min remote queries)
- Additional compute: ~1-5 CHC/month (RMV execution)

**Example** (5 services, 90-day retention):
- Storage: ~1GB
- Compute: ~2 CHC/month
- **Total**: ~3-5 CHC/month

### Q5: Can I use this with On-Premise ClickHouse?

**A**: No. CostKeeper Multi-Service는 ClickHouse Cloud 전용입니다.

**Reasons:**
- CHC API for billing data (not available for on-premise)
- SharedMergeTree table engine (CHC only)
- Refreshable Materialized Views (ClickHouse 24.4+, CHC default)

---

## Support & Feedback

**Documentation**: [DESIGN.md](./DESIGN.md)
**TODO**: [TODO_MULTI_SERVICE_MONITORING.md](../costkeeper/TODO_MULTI_SERVICE_MONITORING.md)
**Issues**: Create an issue in the repository

---

**Last Updated**: 2025-12-07
**Version**: 2.0-multi
**Status**: Production Ready
