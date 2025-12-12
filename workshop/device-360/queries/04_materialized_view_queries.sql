-- ========================================
-- Phase 5: Materialized View Performance
-- Compare pre-aggregated vs real-time queries
-- ========================================

-- Test 5.1A: Device Profile Query (Using Materialized View)
-- Target: < 50ms
-- Query pre-aggregated device profiles
SELECT
    device_id,
    minMerge(first_seen) as first_seen,
    maxMerge(last_seen) as last_seen,
    countMerge(total_events) as total_events,
    uniqMerge(unique_apps) as unique_apps,
    uniqMerge(unique_ips) as unique_ips,
    uniqMerge(unique_countries) as unique_countries,
    avgMerge(avg_fraud_score_ifa) as avg_fraud_score_ifa,
    dateDiff('day', minMerge(first_seen), maxMerge(last_seen)) as lifetime_days
FROM device360.device_profiles
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
GROUP BY device_id;


-- Test 5.1B: Device Profile Query (From Raw Table)
-- Compare performance with materialized view
SELECT
    device_id,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen,
    count() as total_events,
    uniq(app_id) as unique_apps,
    uniq(device_ip) as unique_ips,
    uniq(geo_country) as unique_countries,
    avg(fraud_score_ifa) as avg_fraud_score_ifa,
    dateDiff('day', min(event_ts), max(event_ts)) as lifetime_days
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
GROUP BY device_id;


-- Test 5.2A: Daily Stats Query (Using Materialized View)
-- Target: < 50ms
SELECT
    device_id,
    event_date,
    sum(request_count) as requests,
    sum(unique_ips) as ips,
    sum(unique_apps) as apps,
    sum(total_response_bytes) / 1024 / 1024 as mb_transferred,
    avg(avg_latency_ms) as avg_latency,
    max(max_fraud_score) as max_fraud
FROM device360.device_daily_stats
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
  AND event_date >= today() - 30
GROUP BY device_id, event_date
ORDER BY event_date;


-- Test 5.2B: Daily Stats Query (From Raw Table)
SELECT
    device_id,
    event_date,
    count() as requests,
    uniq(device_ip) as ips,
    uniq(app_id) as apps,
    sum(response_size_bytes) / 1024 / 1024 as mb_transferred,
    avg(response_latency_ms) as avg_latency,
    max(greatest(fraud_score_ifa, fraud_score_ip)) as max_fraud
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
  AND event_date >= today() - 30
GROUP BY device_id, event_date
ORDER BY event_date;


-- Test 5.3A: Bot Candidates Query (Using Materialized View)
-- Target: < 100ms
SELECT
    device_id,
    event_date,
    countMerge(request_count) as requests,
    uniqMerge(unique_ips) as ips,
    uniqMerge(unique_countries) as countries,
    avgMerge(avg_fraud_score) as fraud_score
FROM device360.bot_candidates
WHERE event_date >= today() - 7
GROUP BY device_id, event_date
HAVING requests > 500
ORDER BY requests DESC
LIMIT 100;


-- Test 5.3B: Bot Candidates Query (From Raw Table)
SELECT
    device_id,
    event_date,
    count() as requests,
    uniq(device_ip) as ips,
    uniq(geo_country) as countries,
    avg(greatest(fraud_score_ifa, fraud_score_ip)) as fraud_score
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id, event_date
HAVING requests > 500
ORDER BY requests DESC
LIMIT 100;


-- Test 5.4A: Hourly App Stats (Using Materialized View)
-- Target: < 50ms
SELECT
    app_name,
    event_date,
    event_hour,
    sum(request_count) as requests,
    sum(unique_devices) as devices,
    avg(avg_cpm) as avg_cpm,
    sum(total_response_bytes) / 1024 / 1024 as total_mb
FROM device360.hourly_app_stats
WHERE event_date >= today() - 7
  AND app_name = 'GameApp'
GROUP BY app_name, event_date, event_hour
ORDER BY event_date, event_hour;


-- Test 5.4B: Hourly App Stats (From Raw Table)
SELECT
    app_name,
    event_date,
    event_hour,
    count() as requests,
    uniq(device_id) as devices,
    avg(final_cpm) as avg_cpm,
    sum(response_size_bytes) / 1024 / 1024 as total_mb
FROM device360.ad_requests
WHERE event_date >= today() - 7
  AND app_name = 'GameApp'
GROUP BY app_name, event_date, event_hour
ORDER BY event_date, event_hour;


-- Test 5.5A: Geographic Stats (Using Materialized View)
-- Target: < 50ms
SELECT
    geo_country,
    geo_city,
    sum(request_count) as requests,
    sum(unique_devices) as devices,
    avg(avg_fraud_score) as fraud_score
FROM device360.geo_stats
WHERE event_date >= today() - 7
  AND geo_country = 'US'
GROUP BY geo_country, geo_city
ORDER BY requests DESC
LIMIT 50;


-- Test 5.5B: Geographic Stats (From Raw Table)
SELECT
    geo_country,
    geo_city,
    count() as requests,
    uniq(device_id) as devices,
    avg(greatest(fraud_score_ifa, fraud_score_ip)) as fraud_score
FROM device360.ad_requests
WHERE event_date >= today() - 7
  AND geo_country = 'US'
GROUP BY geo_country, geo_city
ORDER BY requests DESC
LIMIT 50;


-- Test 5.6: Top Devices by Request Volume
-- Using materialized view for faster aggregation
SELECT
    device_id,
    sum(request_count) as total_requests,
    min(event_date) as first_active,
    max(event_date) as last_active,
    count(DISTINCT event_date) as active_days
FROM device360.device_daily_stats
WHERE event_date >= today() - 30
GROUP BY device_id
ORDER BY total_requests DESC
LIMIT 100;


-- Test 5.7: Device Retention Analysis
-- Using materialized view
WITH first_activity AS (
    SELECT
        device_id,
        min(event_date) as first_date
    FROM device360.device_daily_stats
    WHERE event_date >= today() - 30
    GROUP BY device_id
)
SELECT
    first_date,
    dateDiff('day', first_date, event_date) as days_since_first,
    uniq(device360.device_daily_stats.device_id) as returning_devices
FROM first_activity
JOIN device360.device_daily_stats
    ON first_activity.device_id = device360.device_daily_stats.device_id
WHERE event_date >= today() - 30
GROUP BY first_date, days_since_first
ORDER BY first_date, days_since_first;


-- Test 5.8: App Performance Trends
-- Using materialized view for time-series analysis
SELECT
    app_name,
    toStartOfDay(event_date) as day,
    sum(request_count) as requests,
    sum(unique_devices) as devices,
    avg(avg_cpm) as cpm,
    requests / devices as requests_per_device
FROM device360.hourly_app_stats
WHERE event_date >= today() - 14
GROUP BY app_name, day
ORDER BY app_name, day;


-- Test 5.9: Peak Hour Detection
-- Using materialized view
SELECT
    event_hour,
    sum(request_count) as total_requests,
    avg(request_count) as avg_requests_per_app,
    count(DISTINCT app_name) as active_apps
FROM device360.hourly_app_stats
WHERE event_date >= today() - 7
GROUP BY event_hour
ORDER BY total_requests DESC;


-- Test 5.10: Incremental Update Verification
-- Verify materialized views update correctly
-- Insert test data and check propagation
SELECT
    'device_profiles' as view_name,
    count() as row_count,
    max(maxMerge(last_seen)) as latest_update
FROM device360.device_profiles

UNION ALL

SELECT
    'device_daily_stats' as view_name,
    count() as row_count,
    max(event_date) as latest_update
FROM device360.device_daily_stats

UNION ALL

SELECT
    'bot_candidates' as view_name,
    count() as row_count,
    max(event_date) as latest_update
FROM device360.bot_candidates

UNION ALL

SELECT
    'hourly_app_stats' as view_name,
    count() as row_count,
    max(event_date) as latest_update
FROM device360.hourly_app_stats

UNION ALL

SELECT
    'geo_stats' as view_name,
    count() as row_count,
    max(event_date) as latest_update
FROM device360.geo_stats;


-- Test 5.11: Query Performance Comparison
-- Run same logical query with and without materialized views
-- Record execution times to demonstrate speedup
SELECT
    'Performance Test Summary' as test,
    'Run queries 5.1A vs 5.1B, 5.2A vs 5.2B, etc.' as instructions,
    'Compare execution times using EXPLAIN or query_log' as method;
