-- Materialized Views for Device360 Analysis
-- Pre-aggregated views for faster query performance

-- 1. Device Profile Summary
-- Maintains continuously updated profile for each device
CREATE TABLE IF NOT EXISTS device360.device_profiles
(
    device_id String,
    first_seen AggregateFunction(min, DateTime),
    last_seen AggregateFunction(max, DateTime),
    total_events AggregateFunction(count),
    unique_apps AggregateFunction(uniq, String),
    unique_ips AggregateFunction(uniq, String),
    unique_countries AggregateFunction(uniq, String),
    avg_fraud_score_ifa AggregateFunction(avg, UInt8),
    avg_fraud_score_ip AggregateFunction(avg, UInt8)
)
ENGINE = AggregatingMergeTree()
ORDER BY device_id;

CREATE MATERIALIZED VIEW IF NOT EXISTS device360.device_profiles_mv
TO device360.device_profiles
AS
SELECT
    device_id,
    minState(event_ts) AS first_seen,
    maxState(event_ts) AS last_seen,
    countState() AS total_events,
    uniqState(app_id) AS unique_apps,
    uniqState(device_ip) AS unique_ips,
    uniqState(geo_country) AS unique_countries,
    avgState(fraud_score_ifa) AS avg_fraud_score_ifa,
    avgState(fraud_score_ip) AS avg_fraud_score_ip
FROM device360.ad_requests
GROUP BY device_id;


-- 2. Daily Device Summary
-- Pre-aggregated daily statistics per device
CREATE TABLE IF NOT EXISTS device360.device_daily_stats
(
    device_id String,
    event_date Date,
    request_count UInt64,
    unique_ips UInt64,
    unique_apps UInt64,
    total_response_bytes UInt64,
    avg_latency_ms Float32,
    max_fraud_score UInt8
)
ENGINE = SummingMergeTree()
ORDER BY (device_id, event_date);

CREATE MATERIALIZED VIEW IF NOT EXISTS device360.device_daily_stats_mv
TO device360.device_daily_stats
AS
SELECT
    device_id,
    event_date,
    count() AS request_count,
    uniq(device_ip) AS unique_ips,
    uniq(app_id) AS unique_apps,
    sum(response_size_bytes) AS total_response_bytes,
    avg(response_latency_ms) AS avg_latency_ms,
    max(greatest(fraud_score_ifa, fraud_score_ip)) AS max_fraud_score
FROM device360.ad_requests
GROUP BY device_id, event_date;


-- 3. Bot Detection Candidates
-- Identifies devices exceeding threshold values for request frequency
CREATE TABLE IF NOT EXISTS device360.bot_candidates
(
    device_id String,
    event_date Date,
    request_count AggregateFunction(count),
    unique_ips AggregateFunction(uniq, String),
    unique_countries AggregateFunction(uniq, String),
    avg_fraud_score AggregateFunction(avg, UInt8)
)
ENGINE = AggregatingMergeTree()
ORDER BY (event_date, device_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS device360.bot_candidates_mv
TO device360.bot_candidates
AS
SELECT
    device_id,
    event_date,
    countState() AS request_count,
    uniqState(device_ip) AS unique_ips,
    uniqState(geo_country) AS unique_countries,
    avgState(greatest(fraud_score_ifa, fraud_score_ip)) AS avg_fraud_score
FROM device360.ad_requests
GROUP BY device_id, event_date
HAVING count() > 100;  -- Only track potentially suspicious devices


-- 4. Hourly App Stats
-- Track app-level metrics for performance monitoring
CREATE TABLE IF NOT EXISTS device360.hourly_app_stats
(
    app_name String,
    event_date Date,
    event_hour UInt8,
    request_count UInt64,
    unique_devices UInt64,
    avg_cpm Float32,
    total_response_bytes UInt64
)
ENGINE = SummingMergeTree()
ORDER BY (app_name, event_date, event_hour);

CREATE MATERIALIZED VIEW IF NOT EXISTS device360.hourly_app_stats_mv
TO device360.hourly_app_stats
AS
SELECT
    app_name,
    event_date,
    event_hour,
    count() AS request_count,
    uniq(device_id) AS unique_devices,
    avg(final_cpm) AS avg_cpm,
    sum(response_size_bytes) AS total_response_bytes
FROM device360.ad_requests
GROUP BY app_name, event_date, event_hour;


-- 5. Geographic Request Distribution
-- Track geographic distribution of requests
CREATE TABLE IF NOT EXISTS device360.geo_stats
(
    geo_country String,
    geo_city String,
    event_date Date,
    request_count UInt64,
    unique_devices UInt64,
    avg_fraud_score Float32
)
ENGINE = SummingMergeTree()
ORDER BY (geo_country, geo_city, event_date);

CREATE MATERIALIZED VIEW IF NOT EXISTS device360.geo_stats_mv
TO device360.geo_stats
AS
SELECT
    geo_country,
    geo_city,
    event_date,
    count() AS request_count,
    uniq(device_id) AS unique_devices,
    avg(greatest(fraud_score_ifa, fraud_score_ip)) AS avg_fraud_score
FROM device360.ad_requests
GROUP BY geo_country, geo_city, event_date;
