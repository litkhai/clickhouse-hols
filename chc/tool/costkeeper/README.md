# CostKeeper

[English](#english) | [한국어](#한국어)

---

## English

*English translation of the Korean original, LLM-assisted (2026-10-06).*

**ClickHouse Cloud Cost Monitoring & Alerting System**

Version 2.0 | Last Updated: 2025-12-06

---

### 📋 Table of Contents

- [Introduction](#introduction)
- [Key Features](#key-features)
- [System Architecture](#system-architecture)
- [Data Flow](#data-flow)
- [Table Schemas](#table-schemas)
- [RMV Details](#rmv-details)
- [Quick Start](#quick-start)
- [Installation Guide](#installation-guide)
- [Usage Guide](#usage-guide)
- [Integration with External Systems](#integration-with-external-systems)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)

---

### Introduction

**CostKeeper** is a system that monitors ClickHouse Cloud cost and resource usage in real time and automatically generates alerts when anomalies occur.

#### Key Highlights

✅ **100% ClickHouse Cloud native**
- Automatic refresh based on Refreshable Materialized Views (RMV)
- No external scheduler or cronjob required
- Automatic data management through TTL policies

✅ **15-minute metric collection (prevents data loss)**
- CHC's system.asynchronous_metric_log retains only about 33 minutes
- Collecting every 15 minutes prevents data loss
- Four 15-minute data points are aggregated into one hourly row

✅ **Real-time cost monitoring**
- Tracks hourly CPU, memory, storage, and network cost
- Analyzes resource efficiency and identifies wasted cost
- Calculates the rate of change versus 1, 3, and 24 hours earlier

✅ **Automatic alert system**
- Three severity levels: INFO, WARNING, CRITICAL
- Threshold-based automatic alert generation
- Provides an API for integration with external systems

---

### Key Features

#### 1. 15-minute metric collection

- **Problem**: CHC's system.asynchronous_metric_log retains only about 33 minutes
- **Solution**: Collect metrics every 15 minutes and store them in a separate table
- **Effect**: Long-term analysis is possible without data loss

#### 2. Automated cost analysis

- **15-minute raw data collection**: Collects CPU/memory usage from system.asynchronous_metric_log
- **Hourly aggregation**: Consolidates four 15-minute data points into one hour
- **Dynamic resource lookup**: Checks allocations from CGroupMaxCPU and CGroupMemoryTotal
- **Cost analysis**: Combines Cloud API data with metrics to calculate hourly cost
- **Efficiency metrics**: Analyzes actual utilization against the currently allocated resources
- **Waste identification**: Calculates the cost of unused resources

#### 2. Real-time alert generation

- **Multiple comparison baselines**: Detects changes versus 1h, 3h, and 24h earlier
- **Automatic severity classification**:
  - INFO: 20-30% change
  - WARNING: 30-50% change
  - CRITICAL: 50% or more change
- **Detailed alert message**: Includes the rate of change and the estimated cost impact

#### 3. Dashboards and reporting

- **Real-time dashboard**: View cost, efficiency, and alert status
- **History analysis**: Trend analysis based on past data
- **Custom views**: Query the data from various perspectives

---

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CostKeeper v2.0                            │
│           ClickHouse Cloud Native Cost Monitoring System                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────┐      ┌─────────────────────────────────┐  │
│  │   CHC API (Billing)     │      │  system.asynchronous_metric_log │  │
│  │   • 7 days of data      │      │  • ~33 min retention (CHC limit)│  │
│  │   • Daily cost info     │      │  • CPU, Memory, Disk, Network  │  │
│  └──────────┬──────────────┘      └───────────┬─────────────────────┘  │
│             │                                  │                        │
│             │                                  │                        │
│             ▼                                  ▼                        │
│  ┌─────────────────────────┐      ┌──────────────────────────────────┐ │
│  │  daily_billing          │      │  metrics_15min                   │ │
│  │  [RMV: DAILY +1h]       │      │  [RMV: 15 MIN APPEND]            │ │
│  │  Mode: APPEND           │      │  Mode: APPEND                    │ │
│  │  Engine: Replacing      │      │  Engine: SharedMergeTree         │ │
│  │                         │      │  • Collects data every 15 min    │ │
│  │  • Deduplicated by      │      │  • Sorted by collected_at        │ │
│  │    date, service_id     │      │  • Past data accumulates         │ │
│  │  • Keeps only the row   │      └───────────┬──────────────────────┘ │
│  │    with the latest      │                  │                        │
│  │    api_fetched_at       │                  │                        │
│  └──────────┬──────────────┘                  │                        │
│             │                                  │                        │
│             │                                  ▼                        │
│             │                      ┌──────────────────────────────────┐ │
│             │                      │  hourly_metrics                  │ │
│             │                      │  [RMV: HOURLY +2m APPEND]        │ │
│             │                      │  Mode: APPEND                    │ │
│             │                      │  Engine: SharedMergeTree         │ │
│             │                      │                                  │ │
│             │                      │  • 4 x 15-min rows → 1-hour agg  │ │
│             │                      │  • avg, max, sum operations      │ │
│             │                      │  • Sorted by hour                │ │
│             │                      └───────────┬──────────────────────┘ │
│             │                                  │                        │
│             └──────────────┬───────────────────┘                        │
│                            ▼                                            │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  hourly_analysis                                     │ │
│                │  [RMV: HOURLY +5m APPEND]                            │ │
│                │  Mode: APPEND                                        │ │
│                │  Engine: SharedMergeTree                             │ │
│                │                                                      │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 1. metrics_with_lag CTE                        │ │ │
│                │  │    • hourly_metrics + daily_billing JOIN       │ │ │
│                │  │    • lagInFrame reads 1h/3h/24h earlier data   │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 2. Cost and efficiency calculation             │ │ │
│                │  │    • CPU/Memory efficiency (%)                 │ │ │
│                │  │    • Estimated hourly cost (CHC)               │ │ │
│                │  │    • Wasted cost (unused resources)            │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 3. Alert flag calculation                      │ │ │
│                │  │    • alert_cpu_spike_1h/3h/24h                 │ │ │
│                │  │    • alert_cost_spike_1h/3h/24h                │ │ │
│                │  │    • Automatic threshold-based decision        │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                └─────────────┬────────────────────────────────────────┘ │
│                              │                                          │
│                              ▼                                          │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  mv_alerts (Standard Materialized View)             │ │
│                │  Trigger: INSERT INTO hourly_analysis               │ │
│                │  Filter: WHERE alert_any = 1                        │ │
│                │                                                      │ │
│                │  • Detects hourly_analysis rows with alert_any=1    │ │
│                │  • Generates severity, message automatically        │ │
│                │  • Inserts into the alerts table immediately        │ │
│                └─────────────┬────────────────────────────────────────┘ │
│                              ▼                                          │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  alerts                                              │ │
│                │  Engine: SharedMergeTree                             │ │
│                │                                                      │ │
│                │  • alert_id (UUID, unique identifier)               │ │
│                │  • severity (info/warning/critical)                 │ │
│                │  • message (detailed description)                   │ │
│                │  • acknowledged (whether confirmed)                 │ │
│                │                                                      │ │
│                │  External Systems ◄─────────                         │ │
│                │  (Polling)             Slack, PagerDuty, Webhook    │ │
│                └──────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Dashboard Views                             │   │
│  │  • v_dashboard: real-time cost, efficiency, alerts (last 100 h) │   │
│  │  • v_alerts: unacknowledged alerts (latest 50)                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Data Flow

#### Layer 0: External data sources

##### 1. CHC API (Billing Data)
```
Source: https://api.clickhouse.cloud/v1/organizations/{ORG_ID}/usageCost
├─ Collection range: last 7 days of data
├─ Included information:
│  ├─ date (date)
│  ├─ totalCHC (total cost)
│  ├─ computeCHC (compute cost)
│  ├─ storageCHC (storage cost)
│  └─ networkCHC (network cost)
└─ Refresh cycle: RMV 1 (daily at 01:00)
```

##### 2. system.asynchronous_metric_log (System Metrics)
```
Source: ClickHouse internal system table
├─ Retention: ~33 minutes (CHC limit)
├─ Included information:
│  ├─ CGroupMaxCPU (allocated CPU cores)
│  ├─ CGroupMemoryTotal (allocated memory, bytes)
│  ├─ CGroupMemoryUsed (memory in use, bytes)
│  ├─ CGroupUserTimeNormalized (user CPU cores)
│  ├─ CGroupSystemTimeNormalized (system CPU cores)
│  ├─ FilesystemMainPathTotalBytes (total disk)
│  ├─ FilesystemMainPathUsedBytes (disk used)
│  ├─ NetworkReceiveBytes_eth0 (network receive)
│  ├─ NetworkSendBytes_eth0 (network send)
│  └─ LoadAverage1/5 (system load)
└─ Collection cycle: RMV 2 (every 15 minutes)
```

#### Layer 1: Raw data collection

##### daily_billing (daily billing data)
```
RMV 1: rmv_daily_billing
├─ Schedule: REFRESH EVERY 1 DAY OFFSET 1 HOUR
├─ Run time: daily at 01:00 (UTC)
├─ Mode: APPEND (adds data)
├─ Table engine: ReplacingMergeTree(api_fetched_at)
│  └─ Deduplication: keeps only the row with the latest api_fetched_at per (date, service_id)
├─ Data range: last 7 days
└─ Reason: each daily run inserts the same dates again, so ReplacingMergeTree is needed
```

##### metrics_15min (15-minute metrics)
```
RMV 2: rmv_metrics_15min
├─ Schedule: REFRESH EVERY 15 MINUTE
├─ Run time: 00:00, 00:15, 00:30, 00:45, ...
├─ Mode: APPEND (accumulates data)
├─ Table engine: SharedMergeTree()
├─ Data collection:
│  ├─ Target period: now() - 15 minutes ~ now()
│  ├─ Aggregate functions: avgIf, quantileIf, maxIf, sumIf
│  └─ Timestamp: toStartOfFifteenMinutes(now())
├─ Reasons:
│  ├─ system.asynchronous_metric_log retains only about 33 minutes
│  ├─ Collecting every 15 minutes prevents data loss
│  └─ With an hourly cycle, collection would be attempted after the data is already deleted
└─ Result: a new timestamped row every 15 minutes (no duplicates)
```

**metrics_15min sample data:**
```
collected_at        allocated_cpu  cpu_usage_avg  memory_used_avg_gb
2025-12-06 14:00:00      10.0          2.3              8.5
2025-12-06 14:15:00      10.0          2.5              8.7
2025-12-06 14:30:00      10.0          2.4              8.6
2025-12-06 14:45:00      10.0          2.6              8.9
```

#### Layer 2: Hourly aggregation

##### hourly_metrics (hourly metrics)
```
RMV 3: rmv_hourly_metrics
├─ Schedule: REFRESH EVERY 1 HOUR OFFSET 2 MINUTE
├─ Run time: 01:02, 02:02, 03:02, ... (2 minutes past each hour)
├─ Mode: APPEND (accumulates data)
├─ Table engine: SharedMergeTree()
├─ Processing:
│  ├─ Input: 4 records from metrics_15min (e.g. 14:00, 14:15, 14:30, 14:45)
│  ├─ Target hour: start of now() - 1 HOUR (e.g. the 15:02 run processes 14:00)
│  ├─ Aggregation:
│  │  ├─ CPU/Memory: avg (mean of the 4 values)
│  │  ├─ Max values: max (largest of the 4)
│  │  └─ Disk/Network: sum (total of the 4 values)
│  └─ Timestamp: toStartOfHour(now() - 1 HOUR)
└─ Result: a new timestamped row every hour (no duplicates)
```

**hourly_metrics sample data:**
```
hour                allocated_cpu  cpu_usage_avg  memory_used_avg_gb
2025-12-06 14:00:00      10.0          2.45            8.675
  ↑ Average of four 15-min values: (2.3+2.5+2.4+2.6)/4 = 2.45
```

#### Layer 3: Cost analysis and alerts

##### hourly_analysis (hourly analysis)
```
RMV 4: rmv_hourly_analysis
├─ Schedule: REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
├─ Run time: 01:05, 02:05, 03:05, ... (5 minutes past each hour)
├─ Mode: APPEND (accumulates data)
├─ Table engine: SharedMergeTree()
├─ Processing:
│  ├─ Step 1: metrics_with_lag CTE
│  │  ├─ JOIN hourly_metrics with daily_billing
│  │  ├─ Read earlier hours with the lagInFrame window function
│  │  │  ├─ lag_1h: data from 1 hour ago
│  │  │  ├─ lag_3h: data from 3 hours ago
│  │  │  └─ lag_24h: data from 24 hours ago
│  │  └─ ORDER BY hour ROWS BETWEEN N PRECEDING AND CURRENT ROW
│  │
│  ├─ Step 2: cost and efficiency calculation
│  │  ├─ CPU efficiency: (cpu_usage_avg / allocated_cpu) * 100
│  │  ├─ Memory efficiency: (memory_usage_pct_avg)
│  │  ├─ Estimated hourly cost: (daily_total_chc / 24)
│  │  └─ Wasted cost: ((allocated - used) / allocated) * hourly_cost
│  │
│  └─ Step 3: alert flag calculation
│     ├─ CPU change rate: ((current - lag) / lag) * 100
│     ├─ Cost change rate: ((current - lag) / lag) * 100
│     └─ Threshold comparison:
│        ├─ alert_cpu_spike_1h: |change rate| >= ${ALERT_THRESHOLD_PCT}
│        ├─ alert_cpu_spike_3h: |change rate| >= ${ALERT_THRESHOLD_PCT}
│        ├─ alert_cpu_spike_24h: |change rate| >= ${ALERT_THRESHOLD_PCT}
│        └─ alert_any: true if any of the conditions above is true
└─ Result: a new analysis row every hour (no duplicates)
```

**hourly_analysis sample data:**
```
hour                cpu_eff_pct  hourly_chc  alert_cpu_spike_1h  alert_any
2025-12-06 13:00:00    24.5        0.15              0               0
2025-12-06 14:00:00    24.5        0.15              0               0
2025-12-06 15:00:00    63.2        0.42              1               1
  ↑ CPU usage up 158% (24.5% → 63.2%) → Alert fired
```

#### Layer 4: Alert generation

##### alerts (alerts table)
```
MV: mv_alerts (Standard Materialized View)
├─ Trigger: when an INSERT into hourly_analysis occurs
├─ Filter: WHERE alert_any = 1
├─ Behavior:
│  ├─ Detects rows with alert_any = 1
│  ├─ Computes severity:
│  │  ├─ CRITICAL: |change rate| >= ${CRITICAL_THRESHOLD_PCT}
│  │  ├─ WARNING: |change rate| >= ${WARNING_THRESHOLD_PCT}
│  │  └─ INFO: |change rate| >= ${ALERT_THRESHOLD_PCT}
│  ├─ Generates message: "CPU usage up 158% (estimated cost: $X.XX/day)"
│  └─ INSERTs into the alerts table
└─ Result: when an alert occurs, a record is created in the alerts table immediately
```

#### Timing diagram

```
Time          RMV run                     Data processing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
14:00:00  ─┐
14:15:00   │ RMV 2 (15-min cycle)      4 rows inserted into metrics_15min
14:30:00   │   runs                     - 14:00, 14:15, 14:30, 14:45
14:45:00  ─┘

15:02:00     RMV 3 (hourly +2 min)     1 row inserted into hourly_metrics
                                        - aggregates four 15-min rows → 14:00

15:05:00     RMV 4 (hourly +5 min)     1 row inserted into hourly_analysis
                                        - analyzes hourly_metrics + daily_billing
                                        - compares 13:00, 12:00, previous day 14:00 via lagInFrame
                                        - if alert_any = 1, mv_alerts triggers

15:05:01     mv_alerts (immediate)     inserted into alerts table immediately
                                        - severity, message generated automatically
```

#### APPEND vs REPLACE mode

| RMV | Mode | Reason |
|-----|------|--------|
| rmv_daily_billing | APPEND | The last 7 days are fetched every day, so duplicates are inserted.<br>ReplacingMergeTree deduplicates by (date, service_id) |
| rmv_metrics_15min | APPEND | Inserts data with a **new timestamp** every 15 minutes.<br>No duplicates occur, so rows accumulate |
| rmv_hourly_metrics | APPEND | Inserts data with a **new timestamp** every hour.<br>No duplicates occur, so rows accumulate |
| rmv_hourly_analysis | APPEND | Inserts an analysis result with a **new timestamp** every hour.<br>No duplicates occur, so rows accumulate |

**Key principles:**
- ✅ **Time-series data** (new time every run): APPEND + SharedMergeTree
- ✅ **Data that may duplicate** (same date repeated): APPEND + ReplacingMergeTree

---

### Table Schemas

#### 1. daily_billing (daily billing data)

**Purpose:** Stores daily cost data collected from the CHC API

**Engine:** `ReplacingMergeTree(api_fetched_at)`
- **Reason:** The last 7 days of data are fetched every day, so the same (date, service_id) is duplicated
- **Behavior:** Only the row with the latest `api_fetched_at` is ultimately kept

**ORDER BY:** `(date, service_id)`

**TTL:** `date + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| Column | Type | Description | Unit | Example |
|--------|------|-------------|------|---------|
| date | Date | Billing date | - | 2025-12-06 |
| service_id | String | CHC service UUID | - | c5ccc996-e105-... |
| service_name | String | Service display name | - | production |
| total_chc | Float64 | Total cost | CHC (ClickHouse Credits) | 3.45 |
| compute_chc | Float64 | Compute cost | CHC | 2.10 |
| storage_chc | Float64 | Storage cost | CHC | 1.20 |
| network_chc | Float64 | Network cost | CHC | 0.15 |
| api_fetched_at | DateTime64(3) | API fetch time (version column) | Millisecond | 2025-12-06 01:05:32.123 |

#### 2. metrics_15min (15-minute metrics)

**Purpose:** Stores raw metrics collected every 15 minutes from system.asynchronous_metric_log

**Engine:** `SharedMergeTree()`

**ORDER BY:** `(collected_at, service_name)`

**TTL:** `collected_at + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| collected_at | DateTime | Collection time (15-minute step) | - | toStartOfFifteenMinutes(now()) | 2025-12-06 14:15:00 |
| allocated_cpu | Float64 | Allocated CPU cores | Cores | avgIf(value, metric='CGroupMaxCPU') | 10.0 |
| allocated_memory_gb | Float64 | Allocated memory | GB | avgIf(value, metric='CGroupMemoryTotal') / 1024^3 | 40.0 |
| cpu_usage_avg | Float64 | Average CPU usage | Cores | avgIf(UserTime) + avgIf(SystemTime) | 2.5 |
| cpu_usage_p50 | Float64 | Median CPU usage | Cores | quantileIf(0.5)(UserTime+SystemTime) | 2.3 |
| cpu_usage_p90 | Float64 | CPU usage 90th percentile | Cores | quantileIf(0.9)(UserTime+SystemTime) | 3.1 |
| cpu_usage_p99 | Float64 | CPU usage 99th percentile | Cores | quantileIf(0.99)(UserTime+SystemTime) | 3.8 |
| cpu_usage_max | Float64 | Maximum CPU usage | Cores | maxIf(UserTime) + maxIf(SystemTime) | 4.2 |
| cpu_user_cores | Float64 | User CPU cores | Cores | avgIf(CGroupUserTimeNormalized) | 2.0 |
| cpu_system_cores | Float64 | System CPU cores | Cores | avgIf(CGroupSystemTimeNormalized) | 0.5 |
| memory_used_avg_gb | Float64 | Average memory usage | GB | avgIf(CGroupMemoryUsed) / 1024^3 | 8.5 |
| memory_used_p99_gb | Float64 | Memory usage 99th percentile | GB | quantileIf(0.99)(CGroupMemoryUsed) / 1024^3 | 9.2 |
| memory_used_max_gb | Float64 | Maximum memory usage | GB | maxIf(CGroupMemoryUsed) / 1024^3 | 9.5 |
| memory_usage_pct_avg | Float64 | Average memory utilization | % | (used / total) * 100 | 21.25 |
| memory_usage_pct_p99 | Float64 | Memory utilization 99th percentile | % | (p99_used / total) * 100 | 23.0 |
| memory_usage_pct_max | Float64 | Maximum memory utilization | % | (max_used / total) * 100 | 23.75 |
| disk_read_bytes | Float64 | Disk reads (15-minute total) | Bytes | sumIf(BlockReadBytes*) | 1048576000 |
| disk_write_bytes | Float64 | Disk writes (15-minute total) | Bytes | sumIf(BlockWriteBytes*) | 2097152000 |
| disk_total_gb | Float64 | Total disk capacity | GB | maxIf(FilesystemMainPathTotalBytes) / 1024^3 | 100.0 |
| disk_used_gb | Float64 | Disk usage | GB | maxIf(FilesystemMainPathUsedBytes) / 1024^3 | 25.5 |
| disk_usage_pct | Float64 | Disk utilization | % | (used / total) * 100 | 25.5 |
| network_rx_bytes | Float64 | Network receive (15-minute total) | Bytes | sumIf(NetworkReceiveBytes_eth0) | 524288000 |
| network_tx_bytes | Float64 | Network send (15-minute total) | Bytes | sumIf(NetworkSendBytes_eth0) | 1048576000 |
| load_avg_1m | Float64 | 1-minute load average | - | avgIf(LoadAverage1) | 0.8 |
| load_avg_5m | Float64 | 5-minute load average | - | avgIf(LoadAverage5) | 0.6 |
| processes_running_avg | Float64 | Average running processes | Count | avgIf(OSProcessesRunning) | 3.2 |
| service_name | String | Service display name | - | DEFAULT '${SERVICE_NAME}' | production |

#### 3. hourly_metrics (hourly metrics)

**Purpose:** Aggregates four 15-minute metric rows into one hour

**Engine:** `SharedMergeTree()`

**ORDER BY:** `(hour, service_name)`

**TTL:** `hour + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| hour | DateTime | Hour (on the hour) | - | toStartOfHour(now() - 1 HOUR) | 2025-12-06 14:00:00 |
| allocated_cpu | Float64 | Average allocated CPU | Cores | avg(allocated_cpu) from 4 rows | 10.0 |
| allocated_memory_gb | Float64 | Average allocated memory | GB | avg(allocated_memory_gb) from 4 rows | 40.0 |
| cpu_usage_avg | Float64 | Average CPU usage | Cores | avg(cpu_usage_avg) from 4 rows | 2.45 |
| cpu_usage_p50 | Float64 | Average CPU median | Cores | avg(cpu_usage_p50) from 4 rows | 2.30 |
| cpu_usage_p90 | Float64 | Average CPU 90th percentile | Cores | avg(cpu_usage_p90) from 4 rows | 3.15 |
| cpu_usage_p99 | Float64 | Average CPU 99th percentile | Cores | avg(cpu_usage_p99) from 4 rows | 3.82 |
| cpu_usage_max | Float64 | Maximum CPU usage | Cores | max(cpu_usage_max) from 4 rows | 4.50 |
| cpu_user_cores | Float64 | Average user CPU | Cores | avg(cpu_user_cores) from 4 rows | 2.05 |
| cpu_system_cores | Float64 | Average system CPU | Cores | avg(cpu_system_cores) from 4 rows | 0.48 |
| memory_used_avg_gb | Float64 | Average memory usage | GB | avg(memory_used_avg_gb) from 4 rows | 8.68 |
| memory_used_p99_gb | Float64 | Average memory 99th percentile | GB | avg(memory_used_p99_gb) from 4 rows | 9.35 |
| memory_used_max_gb | Float64 | Maximum memory usage | GB | max(memory_used_max_gb) from 4 rows | 9.80 |
| memory_usage_pct_avg | Float64 | Average memory utilization | % | avg(memory_usage_pct_avg) from 4 rows | 21.70 |
| memory_usage_pct_p99 | Float64 | Average memory 99th percentile | % | avg(memory_usage_pct_p99) from 4 rows | 23.38 |
| memory_usage_pct_max | Float64 | Maximum memory utilization | % | max(memory_usage_pct_max) from 4 rows | 24.50 |
| disk_read_bytes | Float64 | Disk reads (1-hour total) | Bytes | sum(disk_read_bytes) from 4 rows | 4194304000 |
| disk_write_bytes | Float64 | Disk writes (1-hour total) | Bytes | sum(disk_write_bytes) from 4 rows | 8388608000 |
| disk_total_gb | Float64 | Average total disk | GB | avg(disk_total_gb) from 4 rows | 100.0 |
| disk_used_gb | Float64 | Average disk usage | GB | avg(disk_used_gb) from 4 rows | 25.62 |
| disk_usage_pct | Float64 | Average disk utilization | % | avg(disk_usage_pct) from 4 rows | 25.62 |
| network_rx_bytes | Float64 | Network receive (1-hour total) | Bytes | sum(network_rx_bytes) from 4 rows | 2097152000 |
| network_tx_bytes | Float64 | Network send (1-hour total) | Bytes | sum(network_tx_bytes) from 4 rows | 4194304000 |
| load_avg_1m | Float64 | Average 1-minute load | - | avg(load_avg_1m) from 4 rows | 0.75 |
| load_avg_5m | Float64 | Average 5-minute load | - | avg(load_avg_5m) from 4 rows | 0.58 |
| processes_running_avg | Float64 | Average running processes | Count | avg(processes_running_avg) from 4 rows | 3.15 |
| service_name | String | Service display name | - | GROUP BY service_name | production |

#### 4. hourly_analysis (hourly analysis)

**Purpose:** Cost analysis, efficiency calculation, and alert flag generation

**Engine:** `SharedMergeTree()`

**ORDER BY:** `(hour, service_name)`

**TTL:** `hour + INTERVAL ${DATA_RETENTION_DAYS} DAY`

##### Basic information

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| hour | DateTime | Hour (on the hour) | - | from hourly_metrics | 2025-12-06 14:00:00 |
| service_name | String | Service display name | - | from hourly_metrics | production |

##### Resource allocation and usage

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| allocated_cpu | Float64 | Allocated CPU | Cores | from hourly_metrics | 10.0 |
| allocated_memory_gb | Float64 | Allocated memory | GB | from hourly_metrics | 40.0 |
| cpu_usage_avg | Float64 | Average CPU usage | Cores | from hourly_metrics | 2.45 |
| cpu_usage_p99 | Float64 | CPU 99th percentile | Cores | from hourly_metrics | 3.82 |
| cpu_usage_max | Float64 | Maximum CPU usage | Cores | from hourly_metrics | 4.50 |
| memory_usage_pct_avg | Float64 | Average memory utilization | % | from hourly_metrics | 21.70 |
| memory_usage_pct_p99 | Float64 | Memory 99th percentile | % | from hourly_metrics | 23.38 |

##### Efficiency metrics

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| cpu_efficiency_pct | Float64 | CPU efficiency | % | (cpu_usage_avg / allocated_cpu) * 100 | 24.50 |
| cpu_efficiency_p99_pct | Float64 | CPU efficiency (99th percentile basis) | % | (cpu_usage_p99 / allocated_cpu) * 100 | 38.20 |
| memory_efficiency_pct | Float64 | Memory efficiency | % | memory_usage_pct_avg | 21.70 |
| memory_efficiency_p99_pct | Float64 | Memory efficiency (99th percentile) | % | memory_usage_pct_p99 | 23.38 |

##### Cost information

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| daily_total_chc | Float64 | Total daily cost | CHC | from daily_billing | 3.45 |
| estimated_hourly_total_chc | Float64 | Estimated total hourly cost | CHC | daily_total_chc / 24 | 0.14375 |
| estimated_hourly_compute_chc | Float64 | Estimated hourly compute cost | CHC | (compute_chc / total_chc) * hourly | 0.0875 |
| estimated_hourly_storage_chc | Float64 | Estimated hourly storage cost | CHC | (storage_chc / total_chc) * hourly | 0.05 |
| estimated_hourly_network_chc | Float64 | Estimated hourly network cost | CHC | (network_chc / total_chc) * hourly | 0.00625 |

##### Wasted cost calculation

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| unused_cpu_pct | Float64 | Unused CPU share | % | 100 - cpu_efficiency_pct | 75.50 |
| unused_memory_pct | Float64 | Unused memory share | % | 100 - memory_efficiency_pct | 78.30 |
| unused_compute_cost_hourly | Float64 | Unused compute cost | CHC/hour | (unused_cpu% / 100) * compute_chc | 0.0661 |

##### Previous-hour data (lagInFrame)

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| cpu_usage_1h_ago | Float64 | CPU 1 hour ago | Cores | lagInFrame(cpu_usage_avg, 1) | 2.30 |
| cpu_usage_3h_ago | Float64 | CPU 3 hours ago | Cores | lagInFrame(cpu_usage_avg, 3) | 2.10 |
| cpu_usage_24h_ago | Float64 | CPU 24 hours ago | Cores | lagInFrame(cpu_usage_avg, 24) | 1.80 |
| cost_1h_ago | Float64 | Cost 1 hour ago | CHC/hour | lagInFrame(estimated_hourly_total_chc, 1) | 0.14 |
| cost_3h_ago | Float64 | Cost 3 hours ago | CHC/hour | lagInFrame(estimated_hourly_total_chc, 3) | 0.13 |
| cost_24h_ago | Float64 | Cost 24 hours ago | CHC/hour | lagInFrame(estimated_hourly_total_chc, 24) | 0.12 |

##### Change rate calculation

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| cpu_change_pct_1h | Float64 | CPU change rate vs 1 hour ago | % | ((current - lag_1h) / lag_1h) * 100 | 6.52 |
| cpu_change_pct_3h | Float64 | CPU change rate vs 3 hours ago | % | ((current - lag_3h) / lag_3h) * 100 | 16.67 |
| cpu_change_pct_24h | Float64 | CPU change rate vs 24 hours ago | % | ((current - lag_24h) / lag_24h) * 100 | 36.11 |
| cost_change_pct_1h | Float64 | Cost change rate vs 1 hour ago | % | ((current - lag_1h) / lag_1h) * 100 | 2.68 |
| cost_change_pct_3h | Float64 | Cost change rate vs 3 hours ago | % | ((current - lag_3h) / lag_3h) * 100 | 10.58 |
| cost_change_pct_24h | Float64 | Cost change rate vs 24 hours ago | % | ((current - lag_24h) / lag_24h) * 100 | 19.79 |

##### Alert flags

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| alert_cpu_spike_1h | UInt8 | 1-hour CPU spike alert | 0/1 | abs(cpu_change_1h) >= threshold | 0 |
| alert_cpu_spike_3h | UInt8 | 3-hour CPU spike alert | 0/1 | abs(cpu_change_3h) >= threshold | 0 |
| alert_cpu_spike_24h | UInt8 | 24-hour CPU spike alert | 0/1 | abs(cpu_change_24h) >= threshold | 1 |
| alert_cost_spike_1h | UInt8 | 1-hour cost spike alert | 0/1 | abs(cost_change_1h) >= threshold | 0 |
| alert_cost_spike_3h | UInt8 | 3-hour cost spike alert | 0/1 | abs(cost_change_3h) >= threshold | 0 |
| alert_cost_spike_24h | UInt8 | 24-hour cost spike alert | 0/1 | abs(cost_change_24h) >= threshold | 0 |
| alert_any | UInt8 | Any alert fired | 0/1 | OR of all alert flags | 1 |

#### 5. alerts (alert storage)

**Purpose:** Stores and manages generated alerts

**Engine:** `SharedMergeTree()`

**ORDER BY:** `(alert_time, hour, alert_type, comparison_period)`

**TTL:** `alert_time + INTERVAL ${ALERT_RETENTION_DAYS} DAY`

| Column | Type | Description | Unit | Calculation | Example |
|--------|------|-------------|------|-------------|---------|
| alert_id | UUID | Unique alert identifier | - | generateUUIDv4() | 550e8400-e29b-41d4-... |
| alert_time | DateTime64(3) | Alert creation time | Millisecond | now64(3) | 2025-12-06 15:05:23.456 |
| hour | DateTime | Hour the alert refers to | - | from hourly_analysis | 2025-12-06 14:00:00 |
| alert_type | String | Alert type | - | 'cpu' or 'cost' | cpu |
| comparison_period | String | Comparison period | - | '1h', '3h', '24h' | 24h |
| severity | String | Severity | - | 'info', 'warning', 'critical' | warning |
| current_value | Float64 | Current value | Cores or CHC | from hourly_analysis | 2.45 |
| comparison_value | Float64 | Value compared against | Cores or CHC | from lag column | 1.80 |
| pct_change | Float64 | Rate of change | % | from change_pct column | 36.11 |
| estimated_hourly_chc | Float64 | Estimated hourly cost | CHC/hour | from hourly_analysis | 0.14375 |
| potential_daily_impact_chc | Float64 | Estimated daily cost impact | CHC/day | estimated_hourly * 24 | 3.45 |
| message | String | Alert message | - | concat(type, ' ', period, '...') | CPU usage increased 36.1% over 24h... |
| acknowledged | UInt8 | Whether acknowledged | 0/1 | DEFAULT 0 | 0 |
| acknowledged_at | DateTime64(3) | Acknowledgement time | Millisecond | NULL or updated value | NULL |
| service_name | String | Service display name | - | from hourly_analysis | production |

---

### RMV Details

#### RMV 1: rmv_daily_billing (daily billing data collection)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_daily_billing
REFRESH EVERY 1 DAY OFFSET 1 HOUR APPEND
TO costkeeper.daily_billing
```

**Run time:** daily at 01:00 UTC

**How it works:**
1. Calls the CHC API: `https://api.clickhouse.cloud/v1/organizations/{ORG_ID}/usageCost`
2. Query parameters: `from_date=now()-7d`, `to_date=now()`
3. Parses the JSON and extracts the data
4. INSERTs into the daily_billing table (APPEND mode)
5. ReplacingMergeTree deduplicates in the background
   - If the same (date, service_id) exists, only the one with the latest api_fetched_at is kept

**Why APPEND + ReplacingMergeTree?**
- The last 7 days are fetched every day, so existing dates are inserted again
- With REPLACE mode only 7 days would be kept and earlier data would disappear
- APPEND + ReplacingMergeTree preserves long-term history and deduplicates automatically

#### RMV 2: rmv_metrics_15min (15-minute metric collection)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_metrics_15min
REFRESH EVERY 15 MINUTE APPEND
TO costkeeper.metrics_15min
```

**Run time:** 00:00, 00:15, 00:30, 00:45, ...

**How it works:**
1. Compute the target period: `now() - 15 MINUTE` ~ `now()`
2. Query data from system.asynchronous_metric_log
3. Aggregate metrics:
   - `avgIf(value, metric='CGroupMaxCPU')` → allocated_cpu
   - `avgIf(value, metric='CGroupUserTimeNormalized')` → cpu_user_cores
   - `quantileIf(0.5)(value, ...)` → cpu_usage_p50
   - `sumIf(value, metric LIKE 'BlockReadBytes%')` → disk_read_bytes
4. Timestamp: `toStartOfFifteenMinutes(now())`
5. INSERT into the metrics_15min table

**Why a 15-minute cycle?**
- CHC's system.asynchronous_metric_log retains only about 33 minutes
- With an hourly cycle, collection would be attempted after the data is already deleted → data loss
- Collecting every 15 minutes always stays within the valid data range
- Four 15-minute data points are gathered and aggregated into hourly data

**Why APPEND mode?**
- A new timestamped row is inserted every 15 minutes
- Example: 14:00, 14:15, 14:30, 14:45 (all different times)
- No duplicates occur, so rows can accumulate

#### RMV 3: rmv_hourly_metrics (hourly metric aggregation)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_hourly_metrics
REFRESH EVERY 1 HOUR OFFSET 2 MINUTE APPEND
TO costkeeper.hourly_metrics
```

**Run time:** 01:02, 02:02, 03:02, ... (2 minutes past each hour)

**How it works:**
1. Compute the target hour: `toStartOfHour(now() - 1 HOUR)`
   - Example: the 15:02 run processes 14:00
2. Read 4 rows from metrics_15min
   - WHERE collected_at >= 14:00 AND collected_at < 15:00
   - Result: 14:00, 14:15, 14:30, 14:45
3. Compute aggregates:
   - CPU/Memory: `avg()` (mean of the 4 values)
   - Max values: `max()` (largest of the 4)
   - Disk/Network: `sum()` (total of the 4 values)
4. INSERT into the hourly_metrics table

**Why a +2 minute OFFSET?**
- RMV 2 runs on the hour (00:00) and inserts the last 15-minute data (e.g. 14:45)
- Waiting 2 minutes aggregates only after all 4 data points are ready
- Guarantees data consistency

**Why APPEND mode?**
- A row with a new hour value is inserted every hour
- Example: 13:00, 14:00, 15:00 (all different times)
- No duplicates occur, so rows can accumulate

#### RMV 4: rmv_hourly_analysis (hourly analysis)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_hourly_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE APPEND
TO costkeeper.hourly_analysis
```

**Run time:** 01:05, 02:05, 03:05, ... (5 minutes past each hour)

**How it works:**
1. Compute the target hour: `toStartOfHour(now() - 1 HOUR)`
2. CTE 1: metrics_with_lag
   ```sql
   SELECT
       m.*,
       d.total_chc as daily_total_chc,
       lagInFrame(m.cpu_usage_avg, 1) OVER w as cpu_usage_1h_ago,
       lagInFrame(m.cpu_usage_avg, 3) OVER w as cpu_usage_3h_ago,
       lagInFrame(m.cpu_usage_avg, 24) OVER w as cpu_usage_24h_ago,
       ...
   FROM hourly_metrics m
   LEFT JOIN daily_billing d ON toDate(m.hour) = d.date
   WINDOW w AS (ORDER BY m.hour ROWS BETWEEN 24 PRECEDING AND CURRENT ROW)
   ```
3. Cost and efficiency calculation
   ```sql
   cpu_efficiency_pct = (cpu_usage_avg / allocated_cpu) * 100
   estimated_hourly_total_chc = daily_total_chc / 24
   unused_compute_cost_hourly = (unused_cpu_pct / 100) * compute_chc
   ```
4. Change rate calculation
   ```sql
   cpu_change_pct_1h = ((current - cpu_usage_1h_ago) / cpu_usage_1h_ago) * 100
   ```
5. Alert flag generation
   ```sql
   alert_cpu_spike_1h = IF(abs(cpu_change_pct_1h) >= ${ALERT_THRESHOLD_PCT}, 1, 0)
   ```
6. INSERT into the hourly_analysis table

**Why a +5 minute OFFSET?**
- RMV 3 runs at +2 minutes and inserts data into hourly_metrics
- Waiting until +5 minutes starts the analysis after RMV 3 has finished
- lagInFrame references the past 24 hours of data, so preparation time is needed

**Why APPEND mode?**
- An analysis result with a new hour value is inserted every hour
- No duplicates occur, so rows can accumulate

#### MV: mv_alerts (alert generation)

```sql
CREATE MATERIALIZED VIEW costkeeper.mv_alerts
TO costkeeper.alerts
AS SELECT ... FROM costkeeper.hourly_analysis WHERE alert_any = 1
```

**Trigger:** when an INSERT into hourly_analysis occurs

**How it works:**
1. Runs automatically when a new row is inserted into hourly_analysis
2. Filters with WHERE alert_any = 1
3. Generates the alert data:
   - Computes severity (critical > warning > info)
   - Generates the message
   - Determines alert_type and comparison_period
4. INSERTs into the alerts table immediately

**Standard MV vs RMV:**
- A Standard MV triggers immediately on INSERT (real time)
- An RMV is schedule-based (periodic)
- Alerts need real-time detection, so a Standard MV is used

---

### Quick Start

#### Prerequisites

- **ClickHouse Cloud instance** (CHC only)
- **ClickHouse Cloud API Key** (for collecting billing data)
- `clickhouse-client` CLI tool installed
- Permission to create databases and manage tables

#### ⚠️ Current limitations

**Monitoring scope:**
- ✅ **Billing data**: Collected for all services in the organization (via the CHC API)
- ⚠️ **Metrics data**: Collected only for the single service selected during setup (system metrics limitation)

**Reason**: `system.asynchronous_metric_log` contains only the metrics of the service you are currently connected to.
To collect another service's metrics, you must connect to that service separately.

#### Installation (takes 3 minutes)

```bash
cd /path/to/clickhouse-hols/chc/tool/costkeeper
./setup-costkeeper.sh
```

**Information to enter at the interactive prompts:**

1. **CHC connection information**
   - CHC host (e.g. abc123.us-east-1.aws.clickhouse.cloud)
   - CHC password (hidden input)

2. **CHC API & service selection**
   - Organization ID (UUID)
   - API Key ID
   - API Key Secret (hidden input)
   - **Service selection**: a list of available services is displayed

3. **Database settings**
   - Database name (default: costkeeper)

4. **Alert and retention settings**
   - Alert threshold (%) - default: 20%
   - Warning threshold (%) - default: 30%
   - Critical threshold (%) - default: 50%
   - Analysis data retention (days) - default: 365 days
   - Alert data retention (days) - default: 90 days

#### Verification

```sql
-- Check the dashboard
SELECT * FROM costkeeper.v_dashboard LIMIT 10;

-- Check alerts
SELECT * FROM costkeeper.v_alerts LIMIT 10;

-- Check RMV status
SELECT * FROM system.view_refreshes WHERE database = 'costkeeper';
```

---

### Installation Guide

#### Interactive installation (recommended)

```bash
./setup-costkeeper.sh
```

The installation script automatically does the following:
1. Collects and validates the CHC connection information
2. Collects the CHC API credentials
3. Lists available services and lets you select one
4. Generates configuration files (`.credentials`, `costkeeper.conf`)
5. Generates the SQL script (`costkeeper-setup.sql`)
6. Creates the database and tables
7. Creates the RMVs and views

#### Security

**Generated files:**

| File | Permissions | Contents | Git |
|------|-------------|----------|-----|
| `.credentials` | 600 | CHC password, API Key Secret | ❌ Excluded |
| `costkeeper.conf` | 644 | Non-sensitive settings | ❌ Excluded |
| `.gitignore` | 644 | List of files excluded from Git | ✅ Included |

**Security checklist:**
- ✅ The `.credentials` file is automatically set to permission 600
- ✅ It is added to `.gitignore` automatically to prevent Git commits
- ✅ The password and API Key Secret are not displayed in the terminal
- ⚠️ Never share the `.credentials` file

---

### Usage Guide

#### Viewing the dashboard

```sql
-- Cost and efficiency status for the last 20 hours
SELECT
    hour,
    service_name,
    round(estimated_hourly_total_chc * 24, 2) as daily_chc,
    round(estimated_hourly_total_chc, 4) as hourly_chc,
    round(cpu_usage_avg, 2) as cpu_cores,
    round(cpu_efficiency_pct, 1) as cpu_eff_pct,
    round(unused_compute_cost_hourly, 4) as waste_hourly_chc,
    multiIf(
        alert_cpu_spike_24h = 1, '24h',
        alert_cpu_spike_3h = 1, '3h',
        alert_cpu_spike_1h = 1, '1h',
        'none'
    ) as alert_trigger
FROM costkeeper.v_dashboard
LIMIT 20;
```

#### Viewing alerts

```sql
-- View unacknowledged alerts
SELECT
    alert_time,
    severity,
    alert_type,
    comparison_period,
    round(pct_change, 1) as change_pct,
    round(potential_daily_impact_chc, 2) as daily_impact,
    message
FROM costkeeper.v_alerts
WHERE acknowledged = 0
ORDER BY alert_time DESC;
```

#### Cost trend analysis

```sql
-- Daily cost and efficiency for the last 7 days
SELECT
    toDate(hour) as date,
    round(avg(estimated_hourly_total_chc * 24), 2) as avg_daily_cost_chc,
    round(avg(cpu_efficiency_pct), 1) as avg_cpu_eff_pct,
    round(avg(memory_efficiency_pct), 1) as avg_mem_eff_pct,
    round(sum(unused_compute_cost_hourly), 2) as total_waste_hourly_chc
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 7 DAY
GROUP BY date
ORDER BY date DESC;
```

#### 15-minute detailed analysis

```sql
-- View 15-minute metrics for the last hour
SELECT
    collected_at,
    round(allocated_cpu, 1) as alloc_cpu,
    round(cpu_usage_avg, 2) as cpu_avg,
    round(cpu_usage_p99, 2) as cpu_p99,
    round(memory_usage_pct_avg, 1) as mem_pct,
    round(disk_read_bytes / 1024 / 1024, 2) as disk_read_mb,
    round(network_rx_bytes / 1024 / 1024, 2) as net_rx_mb
FROM costkeeper.metrics_15min
WHERE collected_at >= now() - INTERVAL 1 HOUR
ORDER BY collected_at DESC;
```

#### Checking RMV status

```sql
-- Refreshable Materialized View status
SELECT
    view,
    status,
    last_success_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'costkeeper'
ORDER BY view;
```

---

### Integration with External Systems

For integration with external systems, CostKeeper recommends a polling approach.

#### Slack integration example

```bash
#!/bin/bash
# check-alerts.sh

WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Query unacknowledged alerts
ALERTS=$(clickhouse-client --host=your-host --secure \
  --query="SELECT message, alert_id FROM costkeeper.alerts \
  WHERE acknowledged = 0 AND alert_time >= now() - INTERVAL 5 MINUTE \
  FORMAT JSONEachRow")

# Send to Slack
echo "$ALERTS" | while read -r alert; do
  MESSAGE=$(echo "$alert" | jq -r '.message')
  ALERT_ID=$(echo "$alert" | jq -r '.alert_id')

  curl -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MESSAGE\"}"

  # Mark as acknowledged
  clickhouse-client --host=your-host --secure \
    --query="ALTER TABLE costkeeper.alerts \
    UPDATE acknowledged = 1, acknowledged_at = now64(3) \
    WHERE alert_id = '$ALERT_ID'"
done
```

---

### Advanced Configuration

#### Adjusting alert thresholds

To change the thresholds after installation:

1. Edit the `costkeeper.conf` file:
```bash
ALERT_THRESHOLD_PCT=25.0
WARNING_THRESHOLD_PCT=40.0
CRITICAL_THRESHOLD_PCT=60.0
```

2. Reinstall:
```bash
./setup-costkeeper.sh
```

#### Changing the TTL policy

```sql
-- Change the 15-minute metrics retention (90 days)
ALTER TABLE costkeeper.metrics_15min
MODIFY TTL collected_at + INTERVAL 90 DAY;

-- Change the hourly analysis retention (180 days)
ALTER TABLE costkeeper.hourly_analysis
MODIFY TTL hour + INTERVAL 180 DAY;
```

#### Changing the RMV collection interval

```sql
-- Change from 15 minutes to 10 minutes
DROP VIEW costkeeper.rmv_metrics_15min;

CREATE MATERIALIZED VIEW costkeeper.rmv_metrics_15min
REFRESH EVERY 10 MINUTE APPEND
TO costkeeper.metrics_15min
AS
-- ... (same SELECT query)
```

---

### Troubleshooting

#### RMV is not running

```sql
-- Check RMV status
SELECT view, status, exception, last_success_time
FROM system.view_refreshes
WHERE database = 'costkeeper' AND status != 'Scheduled';

-- Manually refresh the RMVs
SYSTEM REFRESH VIEW costkeeper.rmv_metrics_15min;
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_metrics;
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_analysis;
```

#### metrics_15min data disappears

**Symptom:** Earlier 15-minute data is not visible

**Cause:** The RMV is running in REPLACE mode instead of APPEND mode

**Fix:**
```sql
-- Check the RMV definition
SHOW CREATE TABLE costkeeper.rmv_metrics_15min;

-- If the APPEND keyword is missing, recreate it
DROP VIEW costkeeper.rmv_metrics_15min;
-- re-run setup-costkeeper.sh
```

#### hourly_metrics is empty

**Symptom:** The hourly_metrics table has no data

**Cause:** metrics_15min does not yet have four 15-minute data points

**Check:**
```sql
-- Check the metrics_15min data
SELECT count(*), min(collected_at), max(collected_at)
FROM costkeeper.metrics_15min
WHERE collected_at >= toStartOfHour(now() - INTERVAL 1 HOUR)
  AND collected_at < toStartOfHour(now());

-- The result should be 4 (00, 15, 30, 45)
```

#### Alerts are not generated

```sql
-- Check the alert flags
SELECT
    hour,
    cpu_change_pct_1h,
    alert_cpu_spike_1h,
    cost_change_pct_1h,
    alert_cost_spike_1h,
    alert_any
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
ORDER BY hour DESC
LIMIT 20;

-- If alert_any = 1 but the alerts table has nothing, check mv_alerts
SELECT count(*) FROM costkeeper.alerts
WHERE alert_time >= now() - INTERVAL 1 HOUR;
```

---

### FAQ

#### Q: Why collect every 15 minutes?

**A:** ClickHouse Cloud's system.asynchronous_metric_log retains only about 33 minutes. If you collect hourly, collection is attempted after the data has already been deleted, causing data loss. Collecting every 15 minutes always stays within the valid data range.

#### Q: What is the difference between APPEND mode and REPLACE mode?

**A:**
- **APPEND mode**: Adds new data to the existing table (accumulates)
- **REPLACE mode**: Completely overwrites the existing table (replaces)

CostKeeper holds time-series data, so all RMVs use APPEND mode.

#### Q: When is ReplacingMergeTree used?

**A:** Only the daily_billing table uses ReplacingMergeTree. The reason is that the last 7 days of data are fetched from the API every day, so the same dates are inserted in duplicate. ReplacingMergeTree keeps only the row with the latest api_fetched_at per (date, service_id), removing duplicates automatically.

#### Q: What is lagInFrame?

**A:** A ClickHouse window function that fetches the value of the row N positions earlier in the rows ordered by ORDER BY. For example, `lagInFrame(cpu_usage_avg, 24) OVER (ORDER BY hour)` returns the cpu_usage_avg value from 24 hours earlier.

#### Q: How do I set the alert thresholds?

**A:** Set them during installation, or edit the `costkeeper.conf` file and re-run `setup-costkeeper.sh`. The defaults are 20% (info), 30% (warning), and 50% (critical).

#### Q: I am worried about data retention cost.

**A:** The TTL policy automatically deletes old data. By default:
- metrics_15min: 365 days
- hourly_metrics: 365 days
- hourly_analysis: 365 days
- alerts: 90 days

#### Q: How is the CPU allocation obtained?

**A:** It is taken directly from the `CGroupMaxCPU` metric in system.asynchronous_metric_log. This value is the actual number of CPU cores that ClickHouse Cloud allocated to the container. It changes automatically on auto-scaling.

#### Q: How does it run automatically without a cronjob?

**A:** It uses ClickHouse's Refreshable Materialized View (RMV) feature. RMVs are executed automatically by ClickHouse's internal scheduler, so no external scheduler is needed.

---

### Tech Stack

- **Database**: ClickHouse Cloud (23.2+)
- **Table Engines**:
  - ReplacingMergeTree: daily_billing (deduplication)
  - SharedMergeTree: all other tables (replication + time series)
- **Automation**: Refreshable Materialized View (RMV)
- **Data Management**: TTL (Time To Live) policy
- **Window Functions**: lagInFrame (comparison with earlier hours)

---

### Project Structure

```
costkeeper/
├── README.md                    # this file
├── setup-costkeeper.sh          # interactive setup script
├── costkeeper-template.sql      # SQL template (with variables)
├── .credentials                 # sensitive info (generated, excluded from Git)
├── costkeeper.conf              # configuration file (generated, excluded from Git)
└── costkeeper-setup.sql         # SQL to run (generated, excluded from Git)
```

---

### Licensing

This project is provided for ClickHouse Cloud users.

---

### Support and Contributing

For questions or bug reports, please file an issue in the issue tracker.

---

**CostKeeper v2.0** - Keep your ClickHouse Cloud costs under control! 💰

Last Updated: 2025-12-06

### License

[MIT](../../../LICENSE) — same as the rest of the repository.

---

## 한국어

**ClickHouse Cloud Cost Monitoring & Alerting System**

Version 2.0 | Last Updated: 2025-12-06

---

### 📋 목차

- [소개](#소개)
- [주요 기능](#주요-기능)
- [시스템 아키텍처](#시스템-아키텍처)
- [데이터 흐름](#데이터-흐름)
- [테이블 스키마](#테이블-스키마)
- [RMV 상세 설명](#rmv-상세-설명)
- [빠른 시작](#빠른-시작)
- [설치 가이드](#설치-가이드)
- [사용 가이드](#사용-가이드)
- [외부 시스템 연동](#외부-시스템-연동)
- [고급 설정](#고급-설정)
- [문제 해결](#문제-해결)
- [FAQ](#faq-1)

---

### 소개

**CostKeeper**는 ClickHouse Cloud의 비용과 리소스 사용량을 실시간으로 모니터링하고, 이상 징후 발생 시 자동으로 Alert를 생성하는 시스템입니다.

#### 핵심 특징

✅ **100% ClickHouse Cloud 네이티브**
- Refreshable Materialized View (RMV) 기반 자동 갱신
- 외부 스케줄러나 cronjob 불필요
- TTL 정책을 통한 자동 데이터 관리

✅ **15분 단위 메트릭 수집 (데이터 손실 방지)**
- CHC의 system.asynchronous_metric_log는 약 33분만 보관
- 15분 주기 수집으로 데이터 손실 방지
- 4개의 15분 데이터를 1시간 단위로 집계

✅ **실시간 비용 모니터링**
- 시간별 CPU, 메모리, 스토리지, 네트워크 비용 추적
- 리소스 효율성 분석 및 낭비 비용 식별
- 1시간, 3시간, 24시간 전 대비 변화율 계산

✅ **자동 Alert 시스템**
- INFO, WARNING, CRITICAL 3단계 심각도 분류
- 임계값 기반 자동 Alert 생성
- 외부 시스템 연동을 위한 API 제공

---

### 주요 기능

#### 1. 15분 단위 메트릭 수집

- **문제**: CHC의 system.asynchronous_metric_log는 약 33분만 보관
- **해결**: 15분마다 메트릭 수집하여 별도 테이블에 저장
- **효과**: 데이터 손실 없이 장기 분석 가능

#### 2. 자동화된 비용 분석

- **15분 단위 원시 데이터 수집**: system.asynchronous_metric_log에서 CPU/메모리 사용량 수집
- **시간별 집계**: 4개의 15분 데이터를 1시간 단위로 통합
- **동적 리소스 조회**: CGroupMaxCPU, CGroupMemoryTotal에서 할당량 확인
- **비용 분석**: Cloud API 데이터와 메트릭을 결합하여 시간별 비용 계산
- **효율성 지표**: 실시간 할당 리소스 대비 실제 사용률 분석
- **낭비 비용 식별**: 미사용 리소스에 대한 비용 계산

#### 2. 실시간 Alert 생성

- **다중 비교 기준**: 1h, 3h, 24h 전 대비 변화 감지
- **자동 심각도 분류**:
  - INFO: 20-30% 변화
  - WARNING: 30-50% 변화
  - CRITICAL: 50% 이상 변화
- **상세 Alert 메시지**: 변화율, 예상 비용 영향 포함

#### 3. 대시보드 및 리포팅

- **실시간 대시보드**: 비용, 효율성, Alert 현황 조회
- **히스토리 분석**: 과거 데이터 기반 트렌드 분석
- **커스텀 View**: 다양한 관점의 데이터 조회

---

### 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CostKeeper v2.0                            │
│           ClickHouse Cloud Native Cost Monitoring System                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────┐      ┌─────────────────────────────────┐  │
│  │   CHC API (Billing)     │      │  system.asynchronous_metric_log │  │
│  │   • 7일 데이터 조회      │      │  • ~33분 보관 (CHC 제한)       │  │
│  │   • 일별 비용 정보       │      │  • CPU, Memory, Disk, Network  │  │
│  └──────────┬──────────────┘      └───────────┬─────────────────────┘  │
│             │                                  │                        │
│             │                                  │                        │
│             ▼                                  ▼                        │
│  ┌─────────────────────────┐      ┌──────────────────────────────────┐ │
│  │  daily_billing          │      │  metrics_15min                   │ │
│  │  [RMV: DAILY +1h]       │      │  [RMV: 15 MIN APPEND]            │ │
│  │  Mode: APPEND           │      │  Mode: APPEND                    │ │
│  │  Engine: Replacing      │      │  Engine: SharedMergeTree         │ │
│  │                         │      │  • 15분마다 데이터 수집           │ │
│  │  • date, service_id로   │      │  • collected_at 기준 정렬        │ │
│  │    중복 제거             │      │  • 과거 데이터 누적 저장          │ │
│  │  • api_fetched_at이     │      └───────────┬──────────────────────┘ │
│  │    최신인 row만 유지     │                  │                        │
│  └──────────┬──────────────┘                  │                        │
│             │                                  │                        │
│             │                                  ▼                        │
│             │                      ┌──────────────────────────────────┐ │
│             │                      │  hourly_metrics                  │ │
│             │                      │  [RMV: HOURLY +2m APPEND]        │ │
│             │                      │  Mode: APPEND                    │ │
│             │                      │  Engine: SharedMergeTree         │ │
│             │                      │                                  │ │
│             │                      │  • 4개 15분 데이터 → 1시간 집계   │ │
│             │                      │  • avg, max, sum 연산            │ │
│             │                      │  • hour 기준 정렬                │ │
│             │                      └───────────┬──────────────────────┘ │
│             │                                  │                        │
│             └──────────────┬───────────────────┘                        │
│                            ▼                                            │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  hourly_analysis                                     │ │
│                │  [RMV: HOURLY +5m APPEND]                            │ │
│                │  Mode: APPEND                                        │ │
│                │  Engine: SharedMergeTree                             │ │
│                │                                                      │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 1. metrics_with_lag CTE                        │ │ │
│                │  │    • hourly_metrics + daily_billing JOIN       │ │ │
│                │  │    • lagInFrame로 1h/3h/24h 이전 데이터 조회    │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 2. 비용 및 효율성 계산                          │ │ │
│                │  │    • CPU/Memory 효율성 (%)                     │ │ │
│                │  │    • 시간당 예상 비용 (CHC)                     │ │ │
│                │  │    • 낭비 비용 (미사용 리소스)                  │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                │  ┌────────────────────────────────────────────────┐ │ │
│                │  │ 3. Alert 플래그 계산                            │ │ │
│                │  │    • alert_cpu_spike_1h/3h/24h                 │ │ │
│                │  │    • alert_cost_spike_1h/3h/24h                │ │ │
│                │  │    • 임계값 기반 자동 판단                      │ │ │
│                │  └────────────────────────────────────────────────┘ │ │
│                └─────────────┬────────────────────────────────────────┘ │
│                              │                                          │
│                              ▼                                          │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  mv_alerts (Standard Materialized View)             │ │
│                │  Trigger: INSERT INTO hourly_analysis               │ │
│                │  Filter: WHERE alert_any = 1                        │ │
│                │                                                      │ │
│                │  • hourly_analysis의 alert_any=1 row 감지           │ │
│                │  • severity, message 자동 생성                       │ │
│                │  • alerts 테이블에 즉시 삽입                         │ │
│                └─────────────┬────────────────────────────────────────┘ │
│                              ▼                                          │
│                ┌──────────────────────────────────────────────────────┐ │
│                │  alerts                                              │ │
│                │  Engine: SharedMergeTree                             │ │
│                │                                                      │ │
│                │  • alert_id (UUID, 고유 식별자)                      │ │
│                │  • severity (info/warning/critical)                 │ │
│                │  • message (상세 설명)                               │ │
│                │  • acknowledged (확인 여부)                          │ │
│                │                                                      │ │
│                │  External Systems ◄─────────                         │ │
│                │  (Polling 방식)        Slack, PagerDuty, Webhook    │ │
│                └──────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Dashboard Views                             │   │
│  │  • v_dashboard: 실시간 비용, 효율성, Alert 현황 (최근 100시간)  │   │
│  │  • v_alerts: 미확인 Alert 조회 (최근 50개)                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 데이터 흐름

#### Layer 0: 외부 데이터 소스

##### 1. CHC API (Billing Data)
```
Source: https://api.clickhouse.cloud/v1/organizations/{ORG_ID}/usageCost
├─ 수집 범위: 최근 7일 데이터
├─ 포함 정보:
│  ├─ date (날짜)
│  ├─ totalCHC (총 비용)
│  ├─ computeCHC (컴퓨팅 비용)
│  ├─ storageCHC (스토리지 비용)
│  └─ networkCHC (네트워크 비용)
└─ 갱신 주기: RMV 1 (매일 01:00)
```

##### 2. system.asynchronous_metric_log (System Metrics)
```
Source: ClickHouse 내부 시스템 테이블
├─ 보관 기간: ~33분 (CHC 제한)
├─ 포함 정보:
│  ├─ CGroupMaxCPU (할당된 CPU 코어)
│  ├─ CGroupMemoryTotal (할당된 메모리, bytes)
│  ├─ CGroupMemoryUsed (사용 중인 메모리, bytes)
│  ├─ CGroupUserTimeNormalized (사용자 CPU 코어)
│  ├─ CGroupSystemTimeNormalized (시스템 CPU 코어)
│  ├─ FilesystemMainPathTotalBytes (디스크 총량)
│  ├─ FilesystemMainPathUsedBytes (디스크 사용량)
│  ├─ NetworkReceiveBytes_eth0 (네트워크 수신)
│  ├─ NetworkSendBytes_eth0 (네트워크 송신)
│  └─ LoadAverage1/5 (시스템 부하)
└─ 수집 주기: RMV 2 (매 15분)
```

#### Layer 1: 원시 데이터 수집

##### daily_billing (일별 청구 데이터)
```
RMV 1: rmv_daily_billing
├─ 실행 주기: REFRESH EVERY 1 DAY OFFSET 1 HOUR
├─ 실행 시각: 매일 01:00 (UTC 기준)
├─ 동작 모드: APPEND (데이터 추가)
├─ 테이블 엔진: ReplacingMergeTree(api_fetched_at)
│  └─ 중복 처리: (date, service_id) 기준으로 api_fetched_at이 최신인 row만 유지
├─ 데이터 범위: 최근 7일
└─ 이유: 매일 실행 시 동일 날짜 데이터가 중복 삽입되므로 ReplacingMergeTree 필요
```

##### metrics_15min (15분 단위 메트릭)
```
RMV 2: rmv_metrics_15min
├─ 실행 주기: REFRESH EVERY 15 MINUTE
├─ 실행 시각: 00:00, 00:15, 00:30, 00:45, ...
├─ 동작 모드: APPEND (데이터 누적)
├─ 테이블 엔진: SharedMergeTree()
├─ 데이터 수집:
│  ├─ 대상 기간: now() - 15분 ~ now()
│  ├─ 집계 함수: avgIf, quantileIf, maxIf, sumIf
│  └─ 타임스탬프: toStartOfFifteenMinutes(now())
├─ 이유:
│  ├─ system.asynchronous_metric_log는 약 33분만 보관
│  ├─ 15분 주기 수집으로 데이터 손실 방지
│  └─ 1시간 주기로는 데이터가 이미 삭제된 후 수집 시도
└─ 결과: 15분 단위로 새로운 타임스탬프 데이터 삽입 (중복 없음)
```

**metrics_15min 데이터 예시:**
```
collected_at        allocated_cpu  cpu_usage_avg  memory_used_avg_gb
2025-12-06 14:00:00      10.0          2.3              8.5
2025-12-06 14:15:00      10.0          2.5              8.7
2025-12-06 14:30:00      10.0          2.4              8.6
2025-12-06 14:45:00      10.0          2.6              8.9
```

#### Layer 2: 시간별 집계

##### hourly_metrics (시간별 메트릭)
```
RMV 3: rmv_hourly_metrics
├─ 실행 주기: REFRESH EVERY 1 HOUR OFFSET 2 MINUTE
├─ 실행 시각: 01:02, 02:02, 03:02, ... (매시 2분)
├─ 동작 모드: APPEND (데이터 누적)
├─ 테이블 엔진: SharedMergeTree()
├─ 데이터 처리:
│  ├─ 입력: metrics_15min의 4개 레코드 (예: 14:00, 14:15, 14:30, 14:45)
│  ├─ 대상 시간: now() - 1 HOUR의 시작 시각 (예: 15:02 실행 시 14:00 처리)
│  ├─ 집계:
│  │  ├─ CPU/Memory: avg (4개 값의 평균)
│  │  ├─ Max 값: max (4개 중 최대값)
│  │  └─ Disk/Network: sum (4개 값의 합계)
│  └─ 타임스탬프: toStartOfHour(now() - 1 HOUR)
└─ 결과: 1시간 단위로 새로운 타임스탬프 데이터 삽입 (중복 없음)
```

**hourly_metrics 데이터 예시:**
```
hour                allocated_cpu  cpu_usage_avg  memory_used_avg_gb
2025-12-06 14:00:00      10.0          2.45            8.675
  ↑ 4개 15분 데이터의 평균: (2.3+2.5+2.4+2.6)/4 = 2.45
```

#### Layer 3: 비용 분석 및 Alert

##### hourly_analysis (시간별 분석)
```
RMV 4: rmv_hourly_analysis
├─ 실행 주기: REFRESH EVERY 1 HOUR OFFSET 5 MINUTE
├─ 실행 시각: 01:05, 02:05, 03:05, ... (매시 5분)
├─ 동작 모드: APPEND (데이터 누적)
├─ 테이블 엔진: SharedMergeTree()
├─ 데이터 처리:
│  ├─ 1단계: metrics_with_lag CTE
│  │  ├─ hourly_metrics와 daily_billing JOIN
│  │  ├─ lagInFrame 윈도우 함수로 이전 시간 데이터 조회
│  │  │  ├─ lag_1h: 1시간 전 데이터
│  │  │  ├─ lag_3h: 3시간 전 데이터
│  │  │  └─ lag_24h: 24시간 전 데이터
│  │  └─ ORDER BY hour ROWS BETWEEN N PRECEDING AND CURRENT ROW
│  │
│  ├─ 2단계: 비용 및 효율성 계산
│  │  ├─ CPU 효율성: (cpu_usage_avg / allocated_cpu) * 100
│  │  ├─ Memory 효율성: (memory_usage_pct_avg)
│  │  ├─ 시간당 예상 비용: (daily_total_chc / 24)
│  │  └─ 낭비 비용: ((allocated - used) / allocated) * hourly_cost
│  │
│  └─ 3단계: Alert 플래그 계산
│     ├─ CPU 변화율: ((current - lag) / lag) * 100
│     ├─ Cost 변화율: ((current - lag) / lag) * 100
│     └─ 임계값 비교:
│        ├─ alert_cpu_spike_1h: |변화율| >= ${ALERT_THRESHOLD_PCT}
│        ├─ alert_cpu_spike_3h: |변화율| >= ${ALERT_THRESHOLD_PCT}
│        ├─ alert_cpu_spike_24h: |변화율| >= ${ALERT_THRESHOLD_PCT}
│        └─ alert_any: 위 조건 중 하나라도 true
└─ 결과: 1시간 단위로 새로운 분석 데이터 삽입 (중복 없음)
```

**hourly_analysis 데이터 예시:**
```
hour                cpu_eff_pct  hourly_chc  alert_cpu_spike_1h  alert_any
2025-12-06 13:00:00    24.5        0.15              0               0
2025-12-06 14:00:00    24.5        0.15              0               0
2025-12-06 15:00:00    63.2        0.42              1               1
  ↑ CPU 사용률 158% 증가 (24.5% → 63.2%) → Alert 발생
```

#### Layer 4: Alert 생성

##### alerts (Alert 테이블)
```
MV: mv_alerts (Standard Materialized View)
├─ 트리거: hourly_analysis에 INSERT 발생 시
├─ 필터: WHERE alert_any = 1
├─ 동작:
│  ├─ alert_any = 1인 row 감지
│  ├─ severity 계산:
│  │  ├─ CRITICAL: |변화율| >= ${CRITICAL_THRESHOLD_PCT}
│  │  ├─ WARNING: |변화율| >= ${WARNING_THRESHOLD_PCT}
│  │  └─ INFO: |변화율| >= ${ALERT_THRESHOLD_PCT}
│  ├─ message 생성: "CPU 사용률 158% 증가 (예상 비용: $X.XX/day)"
│  └─ alerts 테이블에 INSERT
└─ 결과: Alert 발생 시 즉시 alerts 테이블에 레코드 생성
```

#### 타이밍 다이어그램

```
시각          RMV 실행                    데이터 처리
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
14:00:00  ─┐
14:15:00   │ RMV 2 (15분 단위)         metrics_15min에 4개 row 삽입
14:30:00   │   실행                     - 14:00, 14:15, 14:30, 14:45
14:45:00  ─┘

15:02:00     RMV 3 (1시간 +2분)        hourly_metrics에 1개 row 삽입
                                        - 4개 15분 데이터 집계 → 14:00

15:05:00     RMV 4 (1시간 +5분)        hourly_analysis에 1개 row 삽입
                                        - hourly_metrics + daily_billing 분석
                                        - lagInFrame으로 13:00, 12:00, 전일 14:00 비교
                                        - alert_any = 1이면 mv_alerts 트리거

15:05:01     mv_alerts (즉시)          alerts 테이블에 즉시 삽입
                                        - severity, message 자동 생성
```

#### APPEND vs REPLACE 모드

| RMV | 모드 | 이유 |
|-----|------|------|
| rmv_daily_billing | APPEND | 매일 최근 7일 데이터를 가져오므로 중복 삽입 발생.<br>ReplacingMergeTree가 (date, service_id) 기준으로 중복 제거 |
| rmv_metrics_15min | APPEND | 매 15분마다 **새로운 타임스탬프** 데이터 삽입.<br>중복 발생하지 않으므로 누적 저장 |
| rmv_hourly_metrics | APPEND | 매 시간마다 **새로운 타임스탬프** 데이터 삽입.<br>중복 발생하지 않으므로 누적 저장 |
| rmv_hourly_analysis | APPEND | 매 시간마다 **새로운 타임스탬프** 분석 결과 삽입.<br>중복 발생하지 않으므로 누적 저장 |

**핵심 원칙:**
- ✅ **시계열 데이터** (매번 새로운 시간): APPEND + SharedMergeTree
- ✅ **중복 가능 데이터** (같은 날짜 반복): APPEND + ReplacingMergeTree

---

### 테이블 스키마

#### 1. daily_billing (일별 청구 데이터)

**용도:** CHC API에서 수집한 일별 비용 데이터 저장

**엔진:** `ReplacingMergeTree(api_fetched_at)`
- **이유:** 매일 최근 7일 데이터를 가져오므로 동일 (date, service_id) 중복 발생
- **동작:** `api_fetched_at`이 최신인 row만 최종적으로 유지

**ORDER BY:** `(date, service_id)`

**TTL:** `date + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| 컬럼명 | 타입 | 설명 | 단위 | 예시 |
|--------|------|------|------|------|
| date | Date | 청구 날짜 | - | 2025-12-06 |
| service_id | String | CHC 서비스 UUID | - | c5ccc996-e105-... |
| service_name | String | 서비스 표시 이름 | - | production |
| total_chc | Float64 | 총 비용 | CHC (ClickHouse Credits) | 3.45 |
| compute_chc | Float64 | 컴퓨팅 비용 | CHC | 2.10 |
| storage_chc | Float64 | 스토리지 비용 | CHC | 1.20 |
| network_chc | Float64 | 네트워크 비용 | CHC | 0.15 |
| api_fetched_at | DateTime64(3) | API 조회 시각 (버전 컬럼) | Millisecond | 2025-12-06 01:05:32.123 |

#### 2. metrics_15min (15분 단위 메트릭)

**용도:** system.asynchronous_metric_log에서 15분마다 수집한 원시 메트릭 저장

**엔진:** `SharedMergeTree()`

**ORDER BY:** `(collected_at, service_name)`

**TTL:** `collected_at + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| collected_at | DateTime | 수집 시각 (15분 단위) | - | toStartOfFifteenMinutes(now()) | 2025-12-06 14:15:00 |
| allocated_cpu | Float64 | 할당된 CPU 코어 | Cores | avgIf(value, metric='CGroupMaxCPU') | 10.0 |
| allocated_memory_gb | Float64 | 할당된 메모리 | GB | avgIf(value, metric='CGroupMemoryTotal') / 1024^3 | 40.0 |
| cpu_usage_avg | Float64 | 평균 CPU 사용량 | Cores | avgIf(UserTime) + avgIf(SystemTime) | 2.5 |
| cpu_usage_p50 | Float64 | CPU 사용량 중앙값 | Cores | quantileIf(0.5)(UserTime+SystemTime) | 2.3 |
| cpu_usage_p90 | Float64 | CPU 사용량 90%ile | Cores | quantileIf(0.9)(UserTime+SystemTime) | 3.1 |
| cpu_usage_p99 | Float64 | CPU 사용량 99%ile | Cores | quantileIf(0.99)(UserTime+SystemTime) | 3.8 |
| cpu_usage_max | Float64 | 최대 CPU 사용량 | Cores | maxIf(UserTime) + maxIf(SystemTime) | 4.2 |
| cpu_user_cores | Float64 | 사용자 CPU 코어 | Cores | avgIf(CGroupUserTimeNormalized) | 2.0 |
| cpu_system_cores | Float64 | 시스템 CPU 코어 | Cores | avgIf(CGroupSystemTimeNormalized) | 0.5 |
| memory_used_avg_gb | Float64 | 평균 메모리 사용량 | GB | avgIf(CGroupMemoryUsed) / 1024^3 | 8.5 |
| memory_used_p99_gb | Float64 | 메모리 사용량 99%ile | GB | quantileIf(0.99)(CGroupMemoryUsed) / 1024^3 | 9.2 |
| memory_used_max_gb | Float64 | 최대 메모리 사용량 | GB | maxIf(CGroupMemoryUsed) / 1024^3 | 9.5 |
| memory_usage_pct_avg | Float64 | 평균 메모리 사용률 | % | (used / total) * 100 | 21.25 |
| memory_usage_pct_p99 | Float64 | 메모리 사용률 99%ile | % | (p99_used / total) * 100 | 23.0 |
| memory_usage_pct_max | Float64 | 최대 메모리 사용률 | % | (max_used / total) * 100 | 23.75 |
| disk_read_bytes | Float64 | 디스크 읽기 (15분 누적) | Bytes | sumIf(BlockReadBytes*) | 1048576000 |
| disk_write_bytes | Float64 | 디스크 쓰기 (15분 누적) | Bytes | sumIf(BlockWriteBytes*) | 2097152000 |
| disk_total_gb | Float64 | 디스크 총 용량 | GB | maxIf(FilesystemMainPathTotalBytes) / 1024^3 | 100.0 |
| disk_used_gb | Float64 | 디스크 사용량 | GB | maxIf(FilesystemMainPathUsedBytes) / 1024^3 | 25.5 |
| disk_usage_pct | Float64 | 디스크 사용률 | % | (used / total) * 100 | 25.5 |
| network_rx_bytes | Float64 | 네트워크 수신 (15분 누적) | Bytes | sumIf(NetworkReceiveBytes_eth0) | 524288000 |
| network_tx_bytes | Float64 | 네트워크 송신 (15분 누적) | Bytes | sumIf(NetworkSendBytes_eth0) | 1048576000 |
| load_avg_1m | Float64 | 1분 평균 부하 | - | avgIf(LoadAverage1) | 0.8 |
| load_avg_5m | Float64 | 5분 평균 부하 | - | avgIf(LoadAverage5) | 0.6 |
| processes_running_avg | Float64 | 평균 실행 프로세스 수 | Count | avgIf(OSProcessesRunning) | 3.2 |
| service_name | String | 서비스 표시 이름 | - | DEFAULT '${SERVICE_NAME}' | production |

#### 3. hourly_metrics (시간별 메트릭)

**용도:** 4개의 15분 메트릭을 1시간 단위로 집계

**엔진:** `SharedMergeTree()`

**ORDER BY:** `(hour, service_name)`

**TTL:** `hour + INTERVAL ${DATA_RETENTION_DAYS} DAY`

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| hour | DateTime | 시간 (정각) | - | toStartOfHour(now() - 1 HOUR) | 2025-12-06 14:00:00 |
| allocated_cpu | Float64 | 평균 할당 CPU | Cores | avg(allocated_cpu) from 4 rows | 10.0 |
| allocated_memory_gb | Float64 | 평균 할당 메모리 | GB | avg(allocated_memory_gb) from 4 rows | 40.0 |
| cpu_usage_avg | Float64 | 평균 CPU 사용량 | Cores | avg(cpu_usage_avg) from 4 rows | 2.45 |
| cpu_usage_p50 | Float64 | 평균 CPU 중앙값 | Cores | avg(cpu_usage_p50) from 4 rows | 2.30 |
| cpu_usage_p90 | Float64 | 평균 CPU 90%ile | Cores | avg(cpu_usage_p90) from 4 rows | 3.15 |
| cpu_usage_p99 | Float64 | 평균 CPU 99%ile | Cores | avg(cpu_usage_p99) from 4 rows | 3.82 |
| cpu_usage_max | Float64 | 최대 CPU 사용량 | Cores | max(cpu_usage_max) from 4 rows | 4.50 |
| cpu_user_cores | Float64 | 평균 사용자 CPU | Cores | avg(cpu_user_cores) from 4 rows | 2.05 |
| cpu_system_cores | Float64 | 평균 시스템 CPU | Cores | avg(cpu_system_cores) from 4 rows | 0.48 |
| memory_used_avg_gb | Float64 | 평균 메모리 사용량 | GB | avg(memory_used_avg_gb) from 4 rows | 8.68 |
| memory_used_p99_gb | Float64 | 평균 메모리 99%ile | GB | avg(memory_used_p99_gb) from 4 rows | 9.35 |
| memory_used_max_gb | Float64 | 최대 메모리 사용량 | GB | max(memory_used_max_gb) from 4 rows | 9.80 |
| memory_usage_pct_avg | Float64 | 평균 메모리 사용률 | % | avg(memory_usage_pct_avg) from 4 rows | 21.70 |
| memory_usage_pct_p99 | Float64 | 평균 메모리 99%ile | % | avg(memory_usage_pct_p99) from 4 rows | 23.38 |
| memory_usage_pct_max | Float64 | 최대 메모리 사용률 | % | max(memory_usage_pct_max) from 4 rows | 24.50 |
| disk_read_bytes | Float64 | 디스크 읽기 (1시간 누적) | Bytes | sum(disk_read_bytes) from 4 rows | 4194304000 |
| disk_write_bytes | Float64 | 디스크 쓰기 (1시간 누적) | Bytes | sum(disk_write_bytes) from 4 rows | 8388608000 |
| disk_total_gb | Float64 | 평균 디스크 총량 | GB | avg(disk_total_gb) from 4 rows | 100.0 |
| disk_used_gb | Float64 | 평균 디스크 사용량 | GB | avg(disk_used_gb) from 4 rows | 25.62 |
| disk_usage_pct | Float64 | 평균 디스크 사용률 | % | avg(disk_usage_pct) from 4 rows | 25.62 |
| network_rx_bytes | Float64 | 네트워크 수신 (1시간 누적) | Bytes | sum(network_rx_bytes) from 4 rows | 2097152000 |
| network_tx_bytes | Float64 | 네트워크 송신 (1시간 누적) | Bytes | sum(network_tx_bytes) from 4 rows | 4194304000 |
| load_avg_1m | Float64 | 평균 1분 부하 | - | avg(load_avg_1m) from 4 rows | 0.75 |
| load_avg_5m | Float64 | 평균 5분 부하 | - | avg(load_avg_5m) from 4 rows | 0.58 |
| processes_running_avg | Float64 | 평균 실행 프로세스 | Count | avg(processes_running_avg) from 4 rows | 3.15 |
| service_name | String | 서비스 표시 이름 | - | GROUP BY service_name | production |

#### 4. hourly_analysis (시간별 분석)

**용도:** 비용 분석, 효율성 계산, Alert 플래그 생성

**엔진:** `SharedMergeTree()`

**ORDER BY:** `(hour, service_name)`

**TTL:** `hour + INTERVAL ${DATA_RETENTION_DAYS} DAY`

##### 기본 정보

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| hour | DateTime | 시간 (정각) | - | from hourly_metrics | 2025-12-06 14:00:00 |
| service_name | String | 서비스 표시 이름 | - | from hourly_metrics | production |

##### 리소스 할당 및 사용량

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| allocated_cpu | Float64 | 할당 CPU | Cores | from hourly_metrics | 10.0 |
| allocated_memory_gb | Float64 | 할당 메모리 | GB | from hourly_metrics | 40.0 |
| cpu_usage_avg | Float64 | 평균 CPU 사용 | Cores | from hourly_metrics | 2.45 |
| cpu_usage_p99 | Float64 | CPU 99%ile | Cores | from hourly_metrics | 3.82 |
| cpu_usage_max | Float64 | 최대 CPU 사용 | Cores | from hourly_metrics | 4.50 |
| memory_usage_pct_avg | Float64 | 평균 메모리 사용률 | % | from hourly_metrics | 21.70 |
| memory_usage_pct_p99 | Float64 | 메모리 99%ile | % | from hourly_metrics | 23.38 |

##### 효율성 지표

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| cpu_efficiency_pct | Float64 | CPU 효율성 | % | (cpu_usage_avg / allocated_cpu) * 100 | 24.50 |
| cpu_efficiency_p99_pct | Float64 | CPU 효율성 (99%ile 기준) | % | (cpu_usage_p99 / allocated_cpu) * 100 | 38.20 |
| memory_efficiency_pct | Float64 | 메모리 효율성 | % | memory_usage_pct_avg | 21.70 |
| memory_efficiency_p99_pct | Float64 | 메모리 효율성 (99%ile) | % | memory_usage_pct_p99 | 23.38 |

##### 비용 정보

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| daily_total_chc | Float64 | 일일 총 비용 | CHC | from daily_billing | 3.45 |
| estimated_hourly_total_chc | Float64 | 예상 시간당 총 비용 | CHC | daily_total_chc / 24 | 0.14375 |
| estimated_hourly_compute_chc | Float64 | 예상 시간당 컴퓨팅 비용 | CHC | (compute_chc / total_chc) * hourly | 0.0875 |
| estimated_hourly_storage_chc | Float64 | 예상 시간당 스토리지 비용 | CHC | (storage_chc / total_chc) * hourly | 0.05 |
| estimated_hourly_network_chc | Float64 | 예상 시간당 네트워크 비용 | CHC | (network_chc / total_chc) * hourly | 0.00625 |

##### 낭비 비용 계산

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| unused_cpu_pct | Float64 | 미사용 CPU 비율 | % | 100 - cpu_efficiency_pct | 75.50 |
| unused_memory_pct | Float64 | 미사용 메모리 비율 | % | 100 - memory_efficiency_pct | 78.30 |
| unused_compute_cost_hourly | Float64 | 미사용 컴퓨팅 비용 | CHC/hour | (unused_cpu% / 100) * compute_chc | 0.0661 |

##### 이전 시간 데이터 (lagInFrame)

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| cpu_usage_1h_ago | Float64 | 1시간 전 CPU | Cores | lagInFrame(cpu_usage_avg, 1) | 2.30 |
| cpu_usage_3h_ago | Float64 | 3시간 전 CPU | Cores | lagInFrame(cpu_usage_avg, 3) | 2.10 |
| cpu_usage_24h_ago | Float64 | 24시간 전 CPU | Cores | lagInFrame(cpu_usage_avg, 24) | 1.80 |
| cost_1h_ago | Float64 | 1시간 전 비용 | CHC/hour | lagInFrame(estimated_hourly_total_chc, 1) | 0.14 |
| cost_3h_ago | Float64 | 3시간 전 비용 | CHC/hour | lagInFrame(estimated_hourly_total_chc, 3) | 0.13 |
| cost_24h_ago | Float64 | 24시간 전 비용 | CHC/hour | lagInFrame(estimated_hourly_total_chc, 24) | 0.12 |

##### 변화율 계산

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| cpu_change_pct_1h | Float64 | 1시간 전 대비 CPU 변화율 | % | ((current - lag_1h) / lag_1h) * 100 | 6.52 |
| cpu_change_pct_3h | Float64 | 3시간 전 대비 CPU 변화율 | % | ((current - lag_3h) / lag_3h) * 100 | 16.67 |
| cpu_change_pct_24h | Float64 | 24시간 전 대비 CPU 변화율 | % | ((current - lag_24h) / lag_24h) * 100 | 36.11 |
| cost_change_pct_1h | Float64 | 1시간 전 대비 비용 변화율 | % | ((current - lag_1h) / lag_1h) * 100 | 2.68 |
| cost_change_pct_3h | Float64 | 3시간 전 대비 비용 변화율 | % | ((current - lag_3h) / lag_3h) * 100 | 10.58 |
| cost_change_pct_24h | Float64 | 24시간 전 대비 비용 변화율 | % | ((current - lag_24h) / lag_24h) * 100 | 19.79 |

##### Alert 플래그

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| alert_cpu_spike_1h | UInt8 | 1시간 CPU 급증 Alert | 0/1 | abs(cpu_change_1h) >= threshold | 0 |
| alert_cpu_spike_3h | UInt8 | 3시간 CPU 급증 Alert | 0/1 | abs(cpu_change_3h) >= threshold | 0 |
| alert_cpu_spike_24h | UInt8 | 24시간 CPU 급증 Alert | 0/1 | abs(cpu_change_24h) >= threshold | 1 |
| alert_cost_spike_1h | UInt8 | 1시간 비용 급증 Alert | 0/1 | abs(cost_change_1h) >= threshold | 0 |
| alert_cost_spike_3h | UInt8 | 3시간 비용 급증 Alert | 0/1 | abs(cost_change_3h) >= threshold | 0 |
| alert_cost_spike_24h | UInt8 | 24시간 비용 급증 Alert | 0/1 | abs(cost_change_24h) >= threshold | 0 |
| alert_any | UInt8 | 어떤 Alert라도 발생 | 0/1 | OR of all alert flags | 1 |

#### 5. alerts (Alert 저장)

**용도:** 생성된 Alert 저장 및 관리

**엔진:** `SharedMergeTree()`

**ORDER BY:** `(alert_time, hour, alert_type, comparison_period)`

**TTL:** `alert_time + INTERVAL ${ALERT_RETENTION_DAYS} DAY`

| 컬럼명 | 타입 | 설명 | 단위 | 계산 방식 | 예시 |
|--------|------|------|------|-----------|------|
| alert_id | UUID | Alert 고유 식별자 | - | generateUUIDv4() | 550e8400-e29b-41d4-... |
| alert_time | DateTime64(3) | Alert 생성 시각 | Millisecond | now64(3) | 2025-12-06 15:05:23.456 |
| hour | DateTime | Alert 대상 시간 | - | from hourly_analysis | 2025-12-06 14:00:00 |
| alert_type | String | Alert 유형 | - | 'cpu' or 'cost' | cpu |
| comparison_period | String | 비교 기간 | - | '1h', '3h', '24h' | 24h |
| severity | String | 심각도 | - | 'info', 'warning', 'critical' | warning |
| current_value | Float64 | 현재 값 | Cores or CHC | from hourly_analysis | 2.45 |
| comparison_value | Float64 | 비교 대상 값 | Cores or CHC | from lag column | 1.80 |
| pct_change | Float64 | 변화율 | % | from change_pct column | 36.11 |
| estimated_hourly_chc | Float64 | 예상 시간당 비용 | CHC/hour | from hourly_analysis | 0.14375 |
| potential_daily_impact_chc | Float64 | 예상 일일 비용 영향 | CHC/day | estimated_hourly * 24 | 3.45 |
| message | String | Alert 메시지 | - | concat(type, ' ', period, '...') | CPU usage increased 36.1% over 24h... |
| acknowledged | UInt8 | 확인 여부 | 0/1 | DEFAULT 0 | 0 |
| acknowledged_at | DateTime64(3) | 확인 시각 | Millisecond | NULL or updated value | NULL |
| service_name | String | 서비스 표시 이름 | - | from hourly_analysis | production |

---

### RMV 상세 설명

#### RMV 1: rmv_daily_billing (일별 청구 데이터 수집)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_daily_billing
REFRESH EVERY 1 DAY OFFSET 1 HOUR APPEND
TO costkeeper.daily_billing
```

**실행 시간:** 매일 01:00 UTC

**동작 방식:**
1. CHC API 호출: `https://api.clickhouse.cloud/v1/organizations/{ORG_ID}/usageCost`
2. 쿼리 파라미터: `from_date=now()-7d`, `to_date=now()`
3. JSON 파싱 및 데이터 추출
4. daily_billing 테이블에 INSERT (APPEND 모드)
5. ReplacingMergeTree가 백그라운드에서 중복 제거
   - 같은 (date, service_id)가 있으면 api_fetched_at이 최신인 것만 유지

**왜 APPEND + ReplacingMergeTree?**
- 매일 최근 7일 데이터를 가져오므로 기존 날짜 데이터가 중복 삽입됨
- REPLACE 모드를 사용하면 7일만 보관되고 그 이전 데이터는 사라짐
- APPEND + ReplacingMergeTree로 장기 히스토리 보존 + 자동 중복 제거

#### RMV 2: rmv_metrics_15min (15분 메트릭 수집)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_metrics_15min
REFRESH EVERY 15 MINUTE APPEND
TO costkeeper.metrics_15min
```

**실행 시간:** 00:00, 00:15, 00:30, 00:45, ...

**동작 방식:**
1. 대상 기간 계산: `now() - 15 MINUTE` ~ `now()`
2. system.asynchronous_metric_log에서 데이터 조회
3. 메트릭 집계:
   - `avgIf(value, metric='CGroupMaxCPU')` → allocated_cpu
   - `avgIf(value, metric='CGroupUserTimeNormalized')` → cpu_user_cores
   - `quantileIf(0.5)(value, ...)` → cpu_usage_p50
   - `sumIf(value, metric LIKE 'BlockReadBytes%')` → disk_read_bytes
4. 타임스탬프: `toStartOfFifteenMinutes(now())`
5. metrics_15min 테이블에 INSERT

**왜 15분 주기?**
- CHC의 system.asynchronous_metric_log는 약 33분만 보관
- 1시간 주기로는 데이터가 이미 삭제된 후 수집 시도 → 데이터 손실
- 15분 주기로 수집하면 항상 유효한 데이터 범위 내에서 수집 가능
- 4개의 15분 데이터를 모아서 1시간 데이터로 집계

**왜 APPEND 모드?**
- 매 15분마다 새로운 타임스탬프 데이터 삽입
- 예: 14:00, 14:15, 14:30, 14:45 (모두 다른 시간)
- 중복이 발생하지 않으므로 누적 저장 가능

#### RMV 3: rmv_hourly_metrics (시간별 메트릭 집계)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_hourly_metrics
REFRESH EVERY 1 HOUR OFFSET 2 MINUTE APPEND
TO costkeeper.hourly_metrics
```

**실행 시간:** 01:02, 02:02, 03:02, ... (매시 2분)

**동작 방식:**
1. 대상 시간 계산: `toStartOfHour(now() - 1 HOUR)`
   - 예: 15:02 실행 시 → 14:00 처리
2. metrics_15min에서 4개 row 조회
   - WHERE collected_at >= 14:00 AND collected_at < 15:00
   - 결과: 14:00, 14:15, 14:30, 14:45
3. 집계 계산:
   - CPU/Memory: `avg()` (4개 값의 평균)
   - Max 값: `max()` (4개 중 최대값)
   - Disk/Network: `sum()` (4개 값의 합계)
4. hourly_metrics 테이블에 INSERT

**왜 +2분 OFFSET?**
- RMV 2가 정각(00:00)에 실행되어 마지막 15분 데이터(예: 14:45) 삽입
- +2분 대기로 4개 데이터가 모두 준비된 후 집계
- 데이터 정합성 보장

**왜 APPEND 모드?**
- 매 시간마다 새로운 hour 값으로 삽입
- 예: 13:00, 14:00, 15:00 (모두 다른 시간)
- 중복이 발생하지 않으므로 누적 저장 가능

#### RMV 4: rmv_hourly_analysis (시간별 분석)

```sql
CREATE MATERIALIZED VIEW costkeeper.rmv_hourly_analysis
REFRESH EVERY 1 HOUR OFFSET 5 MINUTE APPEND
TO costkeeper.hourly_analysis
```

**실행 시간:** 01:05, 02:05, 03:05, ... (매시 5분)

**동작 방식:**
1. 대상 시간 계산: `toStartOfHour(now() - 1 HOUR)`
2. CTE 1: metrics_with_lag
   ```sql
   SELECT
       m.*,
       d.total_chc as daily_total_chc,
       lagInFrame(m.cpu_usage_avg, 1) OVER w as cpu_usage_1h_ago,
       lagInFrame(m.cpu_usage_avg, 3) OVER w as cpu_usage_3h_ago,
       lagInFrame(m.cpu_usage_avg, 24) OVER w as cpu_usage_24h_ago,
       ...
   FROM hourly_metrics m
   LEFT JOIN daily_billing d ON toDate(m.hour) = d.date
   WINDOW w AS (ORDER BY m.hour ROWS BETWEEN 24 PRECEDING AND CURRENT ROW)
   ```
3. 비용 및 효율성 계산
   ```sql
   cpu_efficiency_pct = (cpu_usage_avg / allocated_cpu) * 100
   estimated_hourly_total_chc = daily_total_chc / 24
   unused_compute_cost_hourly = (unused_cpu_pct / 100) * compute_chc
   ```
4. 변화율 계산
   ```sql
   cpu_change_pct_1h = ((current - cpu_usage_1h_ago) / cpu_usage_1h_ago) * 100
   ```
5. Alert 플래그 생성
   ```sql
   alert_cpu_spike_1h = IF(abs(cpu_change_pct_1h) >= ${ALERT_THRESHOLD_PCT}, 1, 0)
   ```
6. hourly_analysis 테이블에 INSERT

**왜 +5분 OFFSET?**
- RMV 3이 +2분에 실행되어 hourly_metrics에 데이터 삽입
- +5분 대기로 RMV 3 완료 후 분석 시작
- lagInFrame이 과거 24시간 데이터 참조하므로 준비 시간 필요

**왜 APPEND 모드?**
- 매 시간마다 새로운 hour 값으로 분석 결과 삽입
- 중복이 발생하지 않으므로 누적 저장 가능

#### MV: mv_alerts (Alert 생성)

```sql
CREATE MATERIALIZED VIEW costkeeper.mv_alerts
TO costkeeper.alerts
AS SELECT ... FROM costkeeper.hourly_analysis WHERE alert_any = 1
```

**트리거:** hourly_analysis에 INSERT 발생 시

**동작 방식:**
1. hourly_analysis에 새 row 삽입 시 자동 실행
2. WHERE alert_any = 1 필터링
3. Alert 데이터 생성:
   - severity 계산 (critical > warning > info)
   - message 생성
   - alert_type, comparison_period 결정
4. alerts 테이블에 즉시 INSERT

**Standard MV vs RMV:**
- Standard MV는 INSERT 즉시 트리거 (실시간)
- RMV는 스케줄 기반 (주기적)
- Alert는 실시간 감지가 필요하므로 Standard MV 사용

---

### 빠른 시작

#### 전제 조건

- **ClickHouse Cloud 인스턴스** (CHC 전용)
- **ClickHouse Cloud API Key** (Billing 데이터 수집용)
- `clickhouse-client` CLI 도구 설치
- Database 생성 및 테이블 관리 권한

#### ⚠️ 현재 제한사항

**모니터링 범위:**
- ✅ **Billing 데이터**: Organization의 모든 서비스 수집 (CHC API 사용)
- ⚠️ **Metrics 데이터**: 설정 시 선택한 단일 서비스만 수집 (시스템 메트릭 제한)

**이유**: `system.asynchronous_metric_log`는 현재 접속한 서비스의 메트릭만 포함합니다.
다른 서비스의 메트릭을 수집하려면 해당 서비스에 별도로 접속해야 합니다.

#### 설치 (3분 소요)

```bash
cd /path/to/clickhouse-hols/chc/tool/costkeeper
./setup-costkeeper.sh
```

**대화형 프롬프트에서 입력할 정보:**

1. **CHC 연결 정보**
   - CHC 호스트 (예: abc123.us-east-1.aws.clickhouse.cloud)
   - CHC 비밀번호 (숨김 입력)

2. **CHC API & Service 선택**
   - Organization ID (UUID)
   - API Key ID
   - API Key Secret (숨김 입력)
   - **Service 선택**: 사용 가능한 서비스 목록이 표시됩니다

3. **Database 설정**
   - Database 이름 (기본값: costkeeper)

4. **Alert 및 보관 기간 설정**
   - Alert 임계값 (%) - 기본값: 20%
   - Warning 임계값 (%) - 기본값: 30%
   - Critical 임계값 (%) - 기본값: 50%
   - 분석 데이터 보관 기간 (일) - 기본값: 365일
   - Alert 데이터 보관 기간 (일) - 기본값: 90일

#### 확인

```sql
-- Dashboard 확인
SELECT * FROM costkeeper.v_dashboard LIMIT 10;

-- Alert 확인
SELECT * FROM costkeeper.v_alerts LIMIT 10;

-- RMV 상태 확인
SELECT * FROM system.view_refreshes WHERE database = 'costkeeper';
```

---

### 설치 가이드

#### 대화형 설치 (권장)

```bash
./setup-costkeeper.sh
```

설치 스크립트는 다음을 자동으로 수행합니다:
1. CHC 연결 정보 수집 및 검증
2. CHC API 자격 증명 수집
3. 사용 가능한 서비스 목록 조회 및 선택
4. 설정 파일 생성 (`.credentials`, `costkeeper.conf`)
5. SQL 스크립트 생성 (`costkeeper-setup.sql`)
6. 데이터베이스 및 테이블 생성
7. RMV 및 View 생성

#### 보안 관련

**생성되는 파일:**

| 파일 | 권한 | 내용 | Git |
|------|------|------|-----|
| `.credentials` | 600 | CHC 비밀번호, API Key Secret | ❌ 제외 |
| `costkeeper.conf` | 644 | 비민감 설정 | ❌ 제외 |
| `.gitignore` | 644 | Git 제외 파일 목록 | ✅ 포함 |

**보안 체크리스트:**
- ✅ `.credentials` 파일은 자동으로 권한 600 설정
- ✅ `.gitignore`에 자동 추가되어 Git 커밋 방지
- ✅ 비밀번호와 API Key Secret은 터미널에 표시되지 않음
- ⚠️ `.credentials` 파일을 절대 공유하지 마세요

---

### 사용 가이드

#### Dashboard 조회

```sql
-- 최근 20시간 비용 및 효율성 현황
SELECT
    hour,
    service_name,
    round(estimated_hourly_total_chc * 24, 2) as daily_chc,
    round(estimated_hourly_total_chc, 4) as hourly_chc,
    round(cpu_usage_avg, 2) as cpu_cores,
    round(cpu_efficiency_pct, 1) as cpu_eff_pct,
    round(unused_compute_cost_hourly, 4) as waste_hourly_chc,
    multiIf(
        alert_cpu_spike_24h = 1, '24h',
        alert_cpu_spike_3h = 1, '3h',
        alert_cpu_spike_1h = 1, '1h',
        'none'
    ) as alert_trigger
FROM costkeeper.v_dashboard
LIMIT 20;
```

#### Alert 조회

```sql
-- 미확인 Alert 조회
SELECT
    alert_time,
    severity,
    alert_type,
    comparison_period,
    round(pct_change, 1) as change_pct,
    round(potential_daily_impact_chc, 2) as daily_impact,
    message
FROM costkeeper.v_alerts
WHERE acknowledged = 0
ORDER BY alert_time DESC;
```

#### 비용 트렌드 분석

```sql
-- 최근 7일간 일별 비용 및 효율성
SELECT
    toDate(hour) as date,
    round(avg(estimated_hourly_total_chc * 24), 2) as avg_daily_cost_chc,
    round(avg(cpu_efficiency_pct), 1) as avg_cpu_eff_pct,
    round(avg(memory_efficiency_pct), 1) as avg_mem_eff_pct,
    round(sum(unused_compute_cost_hourly), 2) as total_waste_hourly_chc
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 7 DAY
GROUP BY date
ORDER BY date DESC;
```

#### 15분 단위 상세 분석

```sql
-- 최근 1시간 15분 단위 메트릭 조회
SELECT
    collected_at,
    round(allocated_cpu, 1) as alloc_cpu,
    round(cpu_usage_avg, 2) as cpu_avg,
    round(cpu_usage_p99, 2) as cpu_p99,
    round(memory_usage_pct_avg, 1) as mem_pct,
    round(disk_read_bytes / 1024 / 1024, 2) as disk_read_mb,
    round(network_rx_bytes / 1024 / 1024, 2) as net_rx_mb
FROM costkeeper.metrics_15min
WHERE collected_at >= now() - INTERVAL 1 HOUR
ORDER BY collected_at DESC;
```

#### RMV 상태 확인

```sql
-- Refreshable Materialized View 상태
SELECT
    view,
    status,
    last_success_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'costkeeper'
ORDER BY view;
```

---

### 외부 시스템 연동

CostKeeper는 외부 시스템과의 연동을 위해 polling 방식을 권장합니다.

#### Slack 연동 예시

```bash
#!/bin/bash
# check-alerts.sh

WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Query unacknowledged alerts
ALERTS=$(clickhouse-client --host=your-host --secure \
  --query="SELECT message, alert_id FROM costkeeper.alerts \
  WHERE acknowledged = 0 AND alert_time >= now() - INTERVAL 5 MINUTE \
  FORMAT JSONEachRow")

# Send to Slack
echo "$ALERTS" | while read -r alert; do
  MESSAGE=$(echo "$alert" | jq -r '.message')
  ALERT_ID=$(echo "$alert" | jq -r '.alert_id')

  curl -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MESSAGE\"}"

  # Mark as acknowledged
  clickhouse-client --host=your-host --secure \
    --query="ALTER TABLE costkeeper.alerts \
    UPDATE acknowledged = 1, acknowledged_at = now64(3) \
    WHERE alert_id = '$ALERT_ID'"
done
```

---

### 고급 설정

#### Alert 임계값 조정

설치 후 임계값을 변경하려면:

1. `costkeeper.conf` 파일 수정:
```bash
ALERT_THRESHOLD_PCT=25.0
WARNING_THRESHOLD_PCT=40.0
CRITICAL_THRESHOLD_PCT=60.0
```

2. 재설치:
```bash
./setup-costkeeper.sh
```

#### TTL 정책 변경

```sql
-- 15분 메트릭 보관 기간 변경 (90일)
ALTER TABLE costkeeper.metrics_15min
MODIFY TTL collected_at + INTERVAL 90 DAY;

-- 시간별 분석 보관 기간 변경 (180일)
ALTER TABLE costkeeper.hourly_analysis
MODIFY TTL hour + INTERVAL 180 DAY;
```

#### RMV 수집 주기 변경

```sql
-- 15분 → 10분으로 변경
DROP VIEW costkeeper.rmv_metrics_15min;

CREATE MATERIALIZED VIEW costkeeper.rmv_metrics_15min
REFRESH EVERY 10 MINUTE APPEND
TO costkeeper.metrics_15min
AS
-- ... (동일한 SELECT 쿼리)
```

---

### 문제 해결

#### RMV가 실행되지 않음

```sql
-- RMV 상태 확인
SELECT view, status, exception, last_success_time
FROM system.view_refreshes
WHERE database = 'costkeeper' AND status != 'Scheduled';

-- RMV 수동 Refresh
SYSTEM REFRESH VIEW costkeeper.rmv_metrics_15min;
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_metrics;
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_analysis;
```

#### metrics_15min 데이터가 사라짐

**증상:** 이전 15분 데이터가 보이지 않음

**원인:** RMV가 APPEND 모드가 아닌 REPLACE 모드로 실행 중

**해결:**
```sql
-- RMV 정의 확인
SHOW CREATE TABLE costkeeper.rmv_metrics_15min;

-- APPEND 키워드가 없으면 재생성
DROP VIEW costkeeper.rmv_metrics_15min;
-- setup-costkeeper.sh 재실행
```

#### hourly_metrics가 비어있음

**증상:** hourly_metrics 테이블에 데이터가 없음

**원인:** metrics_15min에 4개의 15분 데이터가 준비되지 않음

**확인:**
```sql
-- metrics_15min 데이터 확인
SELECT count(*), min(collected_at), max(collected_at)
FROM costkeeper.metrics_15min
WHERE collected_at >= toStartOfHour(now() - INTERVAL 1 HOUR)
  AND collected_at < toStartOfHour(now());

-- 결과가 4개여야 함 (00, 15, 30, 45)
```

#### Alert가 생성되지 않음

```sql
-- Alert 플래그 확인
SELECT
    hour,
    cpu_change_pct_1h,
    alert_cpu_spike_1h,
    cost_change_pct_1h,
    alert_cost_spike_1h,
    alert_any
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
ORDER BY hour DESC
LIMIT 20;

-- alert_any = 1인데 alerts 테이블에 없으면 mv_alerts 확인
SELECT count(*) FROM costkeeper.alerts
WHERE alert_time >= now() - INTERVAL 1 HOUR;
```

---

### FAQ

#### Q: 왜 15분 단위로 수집하나요?

**A:** ClickHouse Cloud의 system.asynchronous_metric_log는 약 33분만 보관합니다. 1시간 주기로 수집하면 데이터가 이미 삭제된 후 수집을 시도하게 되어 데이터 손실이 발생합니다. 15분 주기로 수집하면 항상 유효한 데이터 범위 내에서 수집할 수 있습니다.

#### Q: APPEND 모드와 REPLACE 모드의 차이는?

**A:**
- **APPEND 모드**: 새 데이터를 기존 테이블에 추가 (누적)
- **REPLACE 모드**: 기존 테이블을 완전히 덮어씀 (교체)

CostKeeper는 시계열 데이터이므로 모든 RMV가 APPEND 모드를 사용합니다.

#### Q: ReplacingMergeTree는 언제 사용하나요?

**A:** daily_billing 테이블만 ReplacingMergeTree를 사용합니다. 이유는 매일 최근 7일 데이터를 API에서 가져오므로 동일 날짜 데이터가 중복 삽입되기 때문입니다. ReplacingMergeTree는 (date, service_id) 기준으로 api_fetched_at이 최신인 row만 유지하여 자동으로 중복을 제거합니다.

#### Q: lagInFrame은 무엇인가요?

**A:** ClickHouse의 윈도우 함수로, ORDER BY로 정렬된 행에서 N번째 이전 행의 값을 가져옵니다. 예를 들어 `lagInFrame(cpu_usage_avg, 24) OVER (ORDER BY hour)`는 24시간 전의 cpu_usage_avg 값을 반환합니다.

#### Q: Alert 임계값은 어떻게 설정하나요?

**A:** 설치 시 설정하거나, `costkeeper.conf` 파일을 수정한 후 `setup-costkeeper.sh`를 재실행하면 됩니다. 기본값은 20% (info), 30% (warning), 50% (critical)입니다.

#### Q: 데이터 보관 비용이 걱정됩니다.

**A:** TTL 정책이 자동으로 오래된 데이터를 삭제합니다. 기본적으로:
- metrics_15min: 365일
- hourly_metrics: 365일
- hourly_analysis: 365일
- alerts: 90일

#### Q: CPU 할당량은 어떻게 가져오나요?

**A:** system.asynchronous_metric_log의 `CGroupMaxCPU` 메트릭에서 직접 가져옵니다. 이 값은 ClickHouse Cloud가 컨테이너에 할당한 실제 CPU 코어 수입니다. Auto-scaling 시 자동으로 변경됩니다.

#### Q: cronjob 없이 어떻게 자동으로 실행되나요?

**A:** ClickHouse의 Refreshable Materialized View (RMV) 기능을 사용합니다. RMV는 ClickHouse 내부 스케줄러에 의해 자동으로 실행되므로 외부 스케줄러가 필요 없습니다.

---

### 기술 스택

- **Database**: ClickHouse Cloud (23.2+)
- **Table Engines**:
  - ReplacingMergeTree: daily_billing (중복 제거)
  - SharedMergeTree: 나머지 모든 테이블 (복제 + 시계열)
- **Automation**: Refreshable Materialized View (RMV)
- **Data Management**: TTL (Time To Live) 정책
- **Window Functions**: lagInFrame (이전 시간대 비교)

---

### 프로젝트 구조

```
costkeeper/
├── README.md                    # 이 파일
├── setup-costkeeper.sh          # 대화형 설정 스크립트
├── costkeeper-template.sql      # SQL 템플릿 (변수 포함)
├── .credentials                 # 민감 정보 (생성됨, Git 제외)
├── costkeeper.conf              # 설정 파일 (생성됨, Git 제외)
└── costkeeper-setup.sql         # 실행용 SQL (생성됨, Git 제외)
```

---

### 라이센스

이 프로젝트는 ClickHouse Cloud 사용자를 위해 제공됩니다.

---

### 지원 및 기여

문의사항이나 버그 리포트는 이슈 트래커에 등록해 주세요.

---

**CostKeeper v2.0** - Keep your ClickHouse Cloud costs under control! 💰

Last Updated: 2025-12-06

### License

[MIT](../../../LICENSE) — same as the rest of the repository.
