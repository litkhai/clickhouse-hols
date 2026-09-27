# Device360 PoC Test Plan
## High-Cardinality Device ID Analysis on ClickHouse

---

## 1. Executive Summary

This PoC validates ClickHouse's capability to handle **Device360-style journey analysis** - a pattern that causes severe performance degradation in BigQuery due to high-cardinality point lookups and sequential event analysis. Unlike traditional aggregation workloads, Device360 analysis requires efficient single-device queries, session reconstruction, and temporal pattern detection.

**Target Data Volume:** 300GB (gzip compressed)
**Primary Challenge:** Point lookup and journey analysis for billions of unique device IDs
**Key Success Criteria:** Sub-second response for individual device journey queries

**Core Use Case Comparison:**

| Analysis Pattern | BigQuery Performance | ClickHouse Target |
|-----------------|---------------------|-------------------|
| Single device lookup | 10-30 seconds | < 100ms |
| Device journey timeline | 30-60 seconds | < 500ms |
| Session reconstruction | 1-2 minutes | < 1 second |
| Cross-app funnel | 30-60 seconds | < 500ms |

The fundamental issue with BigQuery is architectural: it cannot efficiently index high-cardinality columns like device_id. Every device-level query requires scanning substantial portions of data regardless of partitioning strategy. ClickHouse's primary key indexing directly addresses this limitation.

---

## 2. Customer Requirements Analysis

### 2.1 Business Objectives

The customer needs to perform device-level analytics on advertising request data, specifically addressing the limitations experienced with BigQuery when grouping by high-cardinality device IDs. The primary use cases include analyzing request patterns per device and identifying bot traffic for blocking.

### 2.2 Technical Challenges

The Device360 analysis pattern presents unique challenges that differ from typical analytical workloads. Point lookup performance is critical because unlike aggregation queries that scan all data anyway, journey analysis requires finding all events for a single device among billions of records. Session reconstruction complexity arises from calculating time gaps between events using window functions, which requires efficient PARTITION BY device_id execution. Temporal sequence analysis involves analyzing event order, detecting patterns, and calculating metrics like "time since last event" which demands efficient lag/lead operations. Finally, geographic trajectory tracking means calculating distances between consecutive events to detect impossible travel patterns, requiring both window functions and geo calculations.

BigQuery and similar systems struggle because they must perform near-full table scans for device-specific queries, and window functions over high-cardinality partitions create severe memory pressure.

### 2.3 Key Analysis Requirements

The first requirement involves device request frequency analysis, which means calculating daily request counts per device ID to understand usage patterns. The second requirement focuses on bot traffic detection, identifying anomalous devices based on request frequency, IP patterns, and behavioral signals. Future requirements may include device fingerprinting and cross-device analysis.

---

## 3. Data Schema Design

### 3.1 Source Data Characteristics

Based on the sample data analysis, the dataset contains 93 columns covering device information, request metadata, geographic data, buyer/seller details, and various tracking flags. Key identifiers include the `gaid` field (Google Advertising ID) serving as the primary device identifier, along with `ip` address, `request_id`, and app identifiers.

### 3.2 Proposed Schema (Anonymized Column Names)

The schema will be created in a database called `device360`. Column names will be transformed to protect customer data while maintaining analytical capability.

**Core Dimensions:**
- `event_ts` (DateTime) - Request timestamp
- `event_date` (Date) - Partition key derived from timestamp
- `event_hour` (UInt8) - Hour for time-based analysis
- `device_id` (String) - Anonymized from gaid
- `device_ip` (String) - Anonymized from ip
- `device_brand` (LowCardinality String) - Device manufacturer
- `device_model` (LowCardinality String) - Device model
- `os_version` (UInt16) - Operating system version
- `platform_type` (UInt8) - Platform identifier

**Geographic Dimensions:**
- `geo_country` (LowCardinality String) - Country code
- `geo_region` (LowCardinality String) - Region
- `geo_city` (LowCardinality String) - City name
- `geo_continent` (LowCardinality String) - Continent code
- `geo_longitude` (Float32) - Longitude coordinate
- `geo_latitude` (Float32) - Latitude coordinate

**Application Context:**
- `app_id` (String) - Application identifier
- `app_bundle` (String) - Bundle identifier
- `app_name` (LowCardinality String) - Application name
- `app_category` (LowCardinality String) - App category

**Request Metrics:**
- `ad_type` (UInt8) - Advertisement type
- `bid_floor` (Float32) - Minimum bid price
- `final_cpm` (Float32) - Final CPM value
- `response_latency_ms` (UInt16) - Response time
- `response_size_bytes` (UInt32) - Response payload size

**Bot Detection Signals:**
- `fraud_score_ifa` (UInt8) - Pixalate IFA score
- `fraud_score_ip` (UInt8) - Pixalate IP score
- `network_type` (UInt8) - Network connection type
- `screen_density` (UInt16) - Screen density value
- `tracking_consent` (LowCardinality String) - IDFA/opt-in status

---

## 4. Table Architecture

### 4.1 Main Events Table

The primary table `device360.ad_requests` will use the MergeTree engine with careful ORDER BY key design optimized for Device360 query patterns. The ordering key will be `(device_id, event_date, event_ts)` - placing device_id first is critical for efficient point lookups. This differs from typical time-series designs where date comes first, but Device360 patterns prioritize device-level access over time-range scans.

**Key Design Decisions:**

The ORDER BY key structure of `(device_id, event_date, event_ts)` enables millisecond-level single device lookup and efficient date-range filtering within a device. Partitioning by `toYYYYMM(event_date)` balances partition size with data management needs while allowing partition pruning for time-bounded queries.

**Alternative Consideration:**
For workloads requiring both device-centric and time-centric queries, a secondary table with ORDER BY `(event_date, geo_country, device_id)` could be maintained. However, for this PoC focused on Device360 patterns, the device-first ordering is optimal.

### 4.2 Materialized Views for Aggregation

**Device Profile Summary (device360.device_profiles):**
This materialized view maintains a continuously updated profile for each device using AggregatingMergeTree. It tracks first_seen and last_seen timestamps, total lifetime events, unique apps, IPs, and countries visited, plus aggregated fraud scores. The ordering key is simply `(device_id)` for O(1) profile lookups.

**Daily Device Summary (device360.device_daily_stats):**
This materialized view pre-aggregates daily statistics per device using SummingMergeTree. It will track request counts, unique IPs per device, unique apps accessed, total response bytes, average latency, and fraud score indicators. The ordering key will be `(device_id, event_date)` maintaining device-first access pattern.

**Session Pre-computation (device360.device_sessions):**
For frequently accessed devices, pre-computed session boundaries can dramatically improve journey query performance. This view uses AggregatingMergeTree with state functions to maintain session-level aggregates.

**Bot Detection Candidates (device360.bot_candidates):**
A specialized view that identifies devices exceeding threshold values for request frequency, using AggregatingMergeTree with uniqState and countState functions for efficient incremental updates.

---

## 5. Test Scenarios

### 5.1 Phase 1: Device Journey Analysis (Core Use Case)

This is the primary validation phase addressing the customer's core requirement: analyzing individual device behavior patterns that cause severe performance degradation in BigQuery due to high-cardinality point lookups and sequential event analysis.

**Test 1.1 - Single Device Point Lookup:**
```sql
SELECT *
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
ORDER BY event_ts DESC
LIMIT 1000
```
This fundamental query retrieves all events for a specific device. In BigQuery, this requires a full table scan even with partitioning because device_id is not a partition key. ClickHouse's primary key index enables millisecond-level response. **Target: < 100ms**

**Test 1.2 - Device Journey Timeline:**
```sql
SELECT 
    event_ts,
    app_name,
    geo_country,
    geo_city,
    ad_type,
    final_cpm,
    device_ip,
    dateDiff('minute', 
             lagInFrame(event_ts) OVER (ORDER BY event_ts), 
             event_ts) as minutes_since_last
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
  AND event_date >= today() - 30
ORDER BY event_ts
```
This query reconstructs the complete journey of a single device, showing temporal gaps between activities. Essential for understanding user behavior patterns and identifying session boundaries.

**Test 1.3 - Session Detection per Device:**
```sql
WITH device_events AS (
    SELECT 
        event_ts,
        app_name,
        geo_country,
        device_ip,
        dateDiff('minute', 
                 lagInFrame(event_ts) OVER (ORDER BY event_ts), 
                 event_ts) as gap_minutes
    FROM device360.ad_requests
    WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
      AND event_date >= today() - 7
)
SELECT 
    *,
    sum(if(gap_minutes > 30 OR gap_minutes IS NULL, 1, 0)) 
        OVER (ORDER BY event_ts) as session_id
FROM device_events
ORDER BY event_ts
```
Sessions are defined by 30-minute inactivity gaps. This pattern is extremely expensive in BigQuery due to window function execution over high-cardinality partitions.

**Test 1.4 - Device Session Summary:**
```sql
WITH sessions AS (
    SELECT 
        device_id,
        event_ts,
        app_name,
        sum(if(dateDiff('minute', 
               lagInFrame(event_ts) OVER (PARTITION BY device_id ORDER BY event_ts), 
               event_ts) > 30 OR 
               lagInFrame(event_ts) OVER (PARTITION BY device_id ORDER BY event_ts) IS NULL, 
            1, 0)) OVER (PARTITION BY device_id ORDER BY event_ts) as session_id
    FROM device360.ad_requests
    WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
      AND event_date >= today() - 7
)
SELECT 
    session_id,
    min(event_ts) as session_start,
    max(event_ts) as session_end,
    dateDiff('minute', min(event_ts), max(event_ts)) as session_duration_min,
    count() as events_in_session,
    groupArray(DISTINCT app_name) as apps_visited
FROM sessions
GROUP BY device_id, session_id
ORDER BY session_start
```

**Test 1.5 - Cross-App Journey (Funnel Analysis):**
```sql
SELECT 
    device_id,
    groupArray(app_name) as app_sequence,
    groupArray(event_ts) as timestamps,
    length(arrayDistinct(groupArray(app_name))) as unique_apps
FROM (
    SELECT device_id, app_name, event_ts
    FROM device360.ad_requests
    WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
      AND event_date >= today() - 1
    ORDER BY event_ts
)
GROUP BY device_id
```
Tracks the sequence of apps a device interacts with, enabling funnel and path analysis.

**Test 1.6 - Location Journey Analysis:**
```sql
SELECT 
    event_ts,
    geo_country,
    geo_city,
    geo_latitude,
    geo_longitude,
    geoDistance(
        geo_longitude, geo_latitude,
        lagInFrame(geo_longitude) OVER (ORDER BY event_ts),
        lagInFrame(geo_latitude) OVER (ORDER BY event_ts)
    ) / 1000 as distance_km_from_last,
    dateDiff('hour', 
             lagInFrame(event_ts) OVER (ORDER BY event_ts), 
             event_ts) as hours_since_last
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
  AND event_date >= today() - 30
  AND geo_latitude != 0
ORDER BY event_ts
```
Detects impossible travel patterns (e.g., device appearing in Tokyo and New York within 1 hour) which is a strong bot indicator.

**Test 1.7 - Device Behavior Change Detection:**
```sql
WITH daily_patterns AS (
    SELECT 
        event_date,
        count() as daily_requests,
        uniq(app_id) as daily_unique_apps,
        uniq(device_ip) as daily_unique_ips,
        uniq(geo_country) as daily_countries
    FROM device360.ad_requests
    WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
      AND event_date >= today() - 30
    GROUP BY event_date
)
SELECT 
    event_date,
    daily_requests,
    daily_unique_apps,
    avg(daily_requests) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) as avg_7d_requests,
    daily_requests / nullIf(avg(daily_requests) OVER (ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING), 0) as request_ratio
FROM daily_patterns
ORDER BY event_date
```
Identifies sudden behavioral changes that may indicate account takeover or bot conversion.

**Test 1.8 - First/Last Touch Attribution:**
```sql
SELECT 
    device_id,
    argMin(app_name, event_ts) as first_app,
    argMin(geo_country, event_ts) as first_country,
    argMin(event_ts, event_ts) as first_seen,
    argMax(app_name, event_ts) as last_app,
    argMax(geo_country, event_ts) as last_country,
    argMax(event_ts, event_ts) as last_seen,
    dateDiff('day', min(event_ts), max(event_ts)) as device_lifetime_days,
    count() as total_events
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
GROUP BY device_id
```

### 5.2 Phase 2: Schema Validation

**Test 1.1 - Table Creation:**
Create all tables and materialized views in the device360 schema, verifying successful creation and proper configuration.

**Test 1.2 - Sample Data Ingestion:**
Load the provided sample data to validate schema compatibility and data type mappings.

### 5.3 Phase 3: Aggregation Performance Benchmarks

**Test 3.1 - Daily Request Count per Device:**
```sql
SELECT device_id, count() as request_count
FROM device360.ad_requests
WHERE event_date = today() - 1
GROUP BY device_id
ORDER BY request_count DESC
LIMIT 100
```
This query directly addresses the customer's primary use case. Success criteria is sub-second response time.

**Test 3.2 - Device Request Frequency Distribution:**
```sql
SELECT 
    request_count_bucket,
    count() as device_count
FROM (
    SELECT device_id, count() as cnt,
           multiIf(cnt <= 10, '1-10',
                   cnt <= 100, '11-100',
                   cnt <= 1000, '101-1000',
                   '>1000') as request_count_bucket
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    GROUP BY device_id
)
GROUP BY request_count_bucket
```

**Test 3.3 - High-Frequency Device Detection (Bot Candidates):**
```sql
SELECT 
    device_id,
    count() as total_requests,
    uniqExact(device_ip) as unique_ips,
    uniqExact(app_id) as unique_apps,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen
FROM device360.ad_requests
WHERE event_date = today() - 1
GROUP BY device_id
HAVING total_requests > 1000
ORDER BY total_requests DESC
```

**Test 3.4 - Approximate vs Exact Cardinality:**
Compare `uniq()` vs `uniqExact()` performance for device counting to demonstrate ClickHouse's approximate algorithms.

### 5.4 Phase 4: Bot Traffic Analysis

**Test 4.1 - Multi-Signal Bot Detection:**
```sql
SELECT 
    device_id,
    count() as requests,
    uniq(device_ip) as ip_count,
    uniq(geo_country) as country_count,
    avg(fraud_score_ifa) as avg_fraud_score,
    requests / ip_count as requests_per_ip
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING requests > 500 
   AND (ip_count > 10 OR avg_fraud_score > 50 OR country_count > 5)
ORDER BY requests DESC
LIMIT 1000
```

**Test 4.2 - IP-Based Anomaly Detection:**
Identify IPs with excessive device IDs (potential proxy/VPN abuse).

**Test 4.3 - Temporal Pattern Analysis:**
Detect devices with unnaturally consistent request intervals (bot behavior).

### 5.5 Phase 5: Materialized View Performance

**Test 5.1 - Pre-aggregated vs Real-time Query:**
Compare query performance between reading from materialized views versus querying raw data.

**Test 5.2 - Incremental Update Verification:**
Verify materialized views update correctly with new data insertions.

---

## 6. Performance Metrics

### 6.1 Query Performance Targets

**Device Journey Analysis (Primary Focus):**

| Query Type | Target Response Time | BigQuery Baseline | Improvement |
|------------|---------------------|-------------------|-------------|
| Single device point lookup | < 100ms | 10-30 seconds | 100-300x |
| Device journey timeline (30 days) | < 500ms | 30-60 seconds | 60-120x |
| Session detection per device | < 1 second | 1-2 minutes | 60-120x |
| Cross-app funnel analysis | < 500ms | 30-60 seconds | 60-120x |
| Location journey with distance | < 1 second | 1-3 minutes | 60-180x |
| Behavior change detection | < 1 second | 1-2 minutes | 60-120x |

**Aggregation Queries (Secondary):**

| Query Type | Target Response Time | BigQuery Baseline | Improvement |
|------------|---------------------|-------------------|-------------|
| Daily device count (GROUP BY) | < 1 second | 30-60 seconds | 30-60x |
| Weekly aggregation | < 5 seconds | 2-5 minutes | 24-60x |
| Bot detection query | < 3 seconds | 1-3 minutes | 20-60x |
| Cardinality estimation | < 500ms | 10-30 seconds | 20-60x |

### 6.2 Why BigQuery Struggles with Device Journey Analysis

BigQuery's architecture creates fundamental challenges for device-level point lookups. First, partitioning limitations mean BigQuery partitions by date or ingestion time, not by device_id, so queries for a specific device must scan all partitions. Second, clustering helps but is insufficient because while clustering on device_id improves performance, the high cardinality (billions of devices) limits effectiveness. Third, window functions over high-cardinality partitions are expensive since PARTITION BY device_id in window functions creates memory pressure proportional to unique device count. Fourth, slot contention occurs because device journey queries compete for slots with other workloads, causing unpredictable latency.

### 6.3 ClickHouse Advantages for Device360 Pattern

ClickHouse addresses these challenges through several mechanisms. Primary key indexing means that with device_id in the ORDER BY key, point lookups use sparse index for direct block access. Efficient window functions benefit from ClickHouse's streaming execution model which handles window functions without materializing entire partitions. There is no slot contention because dedicated compute resources ensure consistent query latency. Additionally, approximate functions like uniq() and quantile() enable fast exploratory analysis.

### 6.4 Resource Utilization Metrics

Memory usage during high-cardinality GROUP BY operations, CPU utilization patterns, disk I/O for cold queries versus warm cache, and network throughput during data ingestion will all be monitored and documented.

---

## 7. Data Generation Strategy

### 7.1 Synthetic Data Requirements

Since the full 300GB dataset is not immediately available for testing, synthetic data will be generated to simulate realistic conditions. The generation will target 100 million records initially, with configurable device_id cardinality ranging from 10 million to 100 million unique values.

### 7.2 Cardinality Distribution

Device ID distribution will follow a power-law pattern where approximately 1% of devices generate 50% of traffic (simulating heavy users and bots), 10% generate 30% of traffic, and 89% generate the remaining 20%. This distribution accurately models real-world advertising traffic patterns.

---

## 8. Success Criteria

### 8.1 Functional Requirements

All queries must return correct results matching expected outputs from sample data validation. Materialized views must maintain consistency with source data. Bot detection queries must identify known test cases inserted into synthetic data.

### 8.2 Performance Requirements

Device-level GROUP BY queries must complete in under 5 seconds for 100M+ rows. Approximate cardinality functions must demonstrate at least 10x speedup over exact calculations. Memory consumption must remain stable during concurrent high-cardinality queries.

### 8.3 Scalability Indicators

Query performance degradation must be sub-linear as data volume increases. The system should demonstrate horizontal scaling capability with additional nodes.

---

## 9. Deliverables

### 9.1 Technical Artifacts

The PoC will produce complete DDL scripts for all tables and materialized views, a benchmark query suite with expected results, a synthetic data generation script, and performance test results documentation.

### 9.2 Documentation

Final deliverables include a performance comparison report (ClickHouse vs BigQuery baseline), optimization recommendations for production deployment, and a cost estimation for ClickHouse Cloud deployment at full scale.

---

## 10. Timeline

| Phase | Duration | Activities |
|-------|----------|------------|
| Phase 1 | Day 1 | Schema creation, sample data validation |
| Phase 2 | Day 2-3 | Query benchmark development and testing |
| Phase 3 | Day 4 | Bot detection query optimization |
| Phase 4 | Day 5 | Materialized view testing, documentation |

---

## 11. Next Steps

Upon approval of this test plan, the immediate next steps are to create the device360 database and table schemas in the connected ClickHouse instance, develop the synthetic data generation script based on sample data patterns, execute the benchmark suite and collect performance metrics, and prepare the final recommendation report.
