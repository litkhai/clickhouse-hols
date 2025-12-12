-- ========================================
-- Phase 3: Aggregation Performance Benchmarks
-- High-cardinality GROUP BY operations
-- ========================================

-- Test 3.1: Daily Request Count per Device
-- Target: < 1 second
-- Customer's primary use case
SELECT device_id, count() as request_count
FROM device360.ad_requests
WHERE event_date = today() - 1
GROUP BY device_id
ORDER BY request_count DESC
LIMIT 100;


-- Test 3.2: Device Request Frequency Distribution
-- Target: < 3 seconds
-- Understanding device behavior patterns
SELECT
    request_count_bucket,
    count() as device_count,
    sum(total_requests) as total_requests_in_bucket
FROM (
    SELECT
        device_id,
        count() as total_requests,
        multiIf(
            total_requests <= 10, '1-10',
            total_requests <= 100, '11-100',
            total_requests <= 1000, '101-1000',
            total_requests <= 10000, '1001-10000',
            '>10000'
        ) as request_count_bucket
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    GROUP BY device_id
)
GROUP BY request_count_bucket
ORDER BY
    CASE request_count_bucket
        WHEN '1-10' THEN 1
        WHEN '11-100' THEN 2
        WHEN '101-1000' THEN 3
        WHEN '1001-10000' THEN 4
        ELSE 5
    END;


-- Test 3.3: High-Frequency Device Detection
-- Target: < 3 seconds
-- Bot candidate identification
SELECT
    device_id,
    count() as total_requests,
    uniqExact(device_ip) as unique_ips,
    uniqExact(app_id) as unique_apps,
    uniqExact(geo_country) as unique_countries,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen,
    dateDiff('hour', min(event_ts), max(event_ts)) as active_hours
FROM device360.ad_requests
WHERE event_date = today() - 1
GROUP BY device_id
HAVING total_requests > 1000
ORDER BY total_requests DESC
LIMIT 100;


-- Test 3.4: Approximate vs Exact Cardinality
-- Demonstrate ClickHouse's approximate algorithms
SELECT
    'Approximate (uniq)' as method,
    uniq(device_id) as unique_devices,
    now() as query_time
FROM device360.ad_requests
WHERE event_date >= today() - 7

UNION ALL

SELECT
    'Exact (uniqExact)' as method,
    uniqExact(device_id) as unique_devices,
    now() as query_time
FROM device360.ad_requests
WHERE event_date >= today() - 7;


-- Test 3.5: Top Apps by Device Reach
-- Target: < 2 seconds
SELECT
    app_name,
    uniq(device_id) as unique_devices,
    count() as total_requests,
    avg(final_cpm) as avg_cpm,
    sum(response_size_bytes) / 1024 / 1024 as total_mb
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY app_name
ORDER BY unique_devices DESC
LIMIT 50;


-- Test 3.6: Geographic Distribution
-- Target: < 2 seconds
SELECT
    geo_country,
    geo_city,
    uniq(device_id) as unique_devices,
    count() as total_requests,
    avg(fraud_score_ifa) as avg_fraud_score
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY geo_country, geo_city
ORDER BY unique_devices DESC
LIMIT 100;


-- Test 3.7: Device Brand/Model Distribution
-- Target: < 2 seconds
SELECT
    device_brand,
    device_model,
    uniq(device_id) as unique_devices,
    count() as total_requests,
    avg(response_latency_ms) as avg_latency_ms
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_brand, device_model
ORDER BY unique_devices DESC
LIMIT 50;


-- Test 3.8: Hourly Request Pattern
-- Target: < 2 seconds
SELECT
    event_date,
    event_hour,
    count() as requests,
    uniq(device_id) as unique_devices,
    avg(final_cpm) as avg_cpm
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY event_date, event_hour
ORDER BY event_date, event_hour;


-- Test 3.9: IP Address Analysis
-- Identify IPs with excessive device IDs (proxy/VPN abuse)
-- Target: < 3 seconds
SELECT
    device_ip,
    uniq(device_id) as unique_devices,
    uniq(geo_country) as unique_countries,
    count() as total_requests
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_ip
HAVING unique_devices > 10
ORDER BY unique_devices DESC
LIMIT 100;


-- Test 3.10: Ad Performance by Type
-- Target: < 2 seconds
SELECT
    ad_type,
    count() as impressions,
    uniq(device_id) as unique_devices,
    avg(bid_floor) as avg_bid_floor,
    avg(final_cpm) as avg_final_cpm,
    quantile(0.5)(final_cpm) as median_cpm,
    quantile(0.95)(final_cpm) as p95_cpm
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY ad_type
ORDER BY impressions DESC;


-- Test 3.11: Time-to-First-Request Distribution
-- New device acquisition analysis
-- Target: < 3 seconds
WITH first_seen AS (
    SELECT
        device_id,
        min(event_date) as first_date
    FROM device360.ad_requests
    GROUP BY device_id
)
SELECT
    first_date,
    count() as new_devices
FROM first_seen
WHERE first_date >= today() - 30
GROUP BY first_date
ORDER BY first_date;


-- Test 3.12: Retention Cohort Analysis
-- Target: < 5 seconds
WITH device_first_day AS (
    SELECT
        device_id,
        toStartOfDay(min(event_ts)) as first_day
    FROM device360.ad_requests
    WHERE event_date >= today() - 30
    GROUP BY device_id
)
SELECT
    first_day,
    dateDiff('day', first_day, event_date) as days_since_first,
    uniq(device360.ad_requests.device_id) as active_devices
FROM device_first_day
JOIN device360.ad_requests ON device_first_day.device_id = device360.ad_requests.device_id
WHERE event_date >= today() - 30
GROUP BY first_day, days_since_first
ORDER BY first_day, days_since_first;
