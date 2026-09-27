-- ========================================
-- Phase 4: Bot Traffic Analysis
-- Multi-signal bot detection queries
-- ========================================

-- Test 4.1: Multi-Signal Bot Detection
-- Target: < 3 seconds
-- Comprehensive bot identification using multiple signals
SELECT
    device_id,
    count() as requests,
    uniq(device_ip) as ip_count,
    uniq(geo_country) as country_count,
    uniq(geo_city) as city_count,
    avg(fraud_score_ifa) as avg_fraud_score_ifa,
    avg(fraud_score_ip) as avg_fraud_score_ip,
    requests / nullIf(ip_count, 0) as requests_per_ip,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen,
    dateDiff('hour', min(event_ts), max(event_ts)) as active_hours,
    requests / nullIf(dateDiff('hour', min(event_ts), max(event_ts)), 0) as requests_per_hour
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING requests > 500
   AND (
       ip_count > 10
       OR avg_fraud_score_ifa > 50
       OR country_count > 5
       OR requests_per_hour > 50
   )
ORDER BY requests DESC
LIMIT 1000;


-- Test 4.2: IP-Based Anomaly Detection
-- Target: < 3 seconds
-- Identify IPs with excessive device IDs (proxy/VPN abuse)
SELECT
    device_ip,
    uniq(device_id) as unique_devices,
    uniq(geo_country) as unique_countries,
    count() as total_requests,
    avg(fraud_score_ip) as avg_fraud_score,
    groupArray(DISTINCT geo_country) as countries
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_ip
HAVING unique_devices > 20
ORDER BY unique_devices DESC
LIMIT 100;


-- Test 4.3: Temporal Pattern Analysis
-- Target: < 3 seconds
-- Detect unnaturally consistent request intervals
WITH device_intervals AS (
    SELECT
        device_id,
        dateDiff('second',
                 lagInFrame(event_ts) OVER (PARTITION BY device_id ORDER BY event_ts),
                 event_ts) as interval_seconds
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    AND device_id IN (
        SELECT device_id
        FROM device360.ad_requests
        WHERE event_date >= today() - 7
        GROUP BY device_id
        HAVING count() > 500
        LIMIT 1000
    )
)
SELECT
    device_id,
    count() as intervals_measured,
    avg(interval_seconds) as avg_interval,
    stddevPop(interval_seconds) as stddev_interval,
    stddevPop(interval_seconds) / nullIf(avg(interval_seconds), 0) as coefficient_of_variation,
    min(interval_seconds) as min_interval,
    max(interval_seconds) as max_interval
FROM device_intervals
WHERE interval_seconds IS NOT NULL
GROUP BY device_id
HAVING coefficient_of_variation < 0.3  -- Low variance = bot-like behavior
ORDER BY coefficient_of_variation ASC
LIMIT 100;


-- Test 4.4: Impossible Travel Detection
-- Target: < 5 seconds
-- Devices appearing in distant locations within short time
WITH device_locations AS (
    SELECT
        device_id,
        event_ts,
        geo_country,
        geo_city,
        geo_latitude,
        geo_longitude,
        lagInFrame(event_ts) OVER (PARTITION BY device_id ORDER BY event_ts) as prev_ts,
        lagInFrame(geo_latitude) OVER (PARTITION BY device_id ORDER BY event_ts) as prev_lat,
        lagInFrame(geo_longitude) OVER (PARTITION BY device_id ORDER BY event_ts) as prev_lon
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    AND geo_latitude != 0
    AND device_id IN (
        SELECT device_id
        FROM device360.ad_requests
        WHERE event_date >= today() - 7
        GROUP BY device_id
        HAVING count() > 100
    )
)
SELECT
    device_id,
    event_ts,
    prev_ts,
    geo_country,
    geo_city,
    geoDistance(geo_longitude, geo_latitude, prev_lon, prev_lat) / 1000 as distance_km,
    dateDiff('hour', prev_ts, event_ts) as hours_elapsed,
    (geoDistance(geo_longitude, geo_latitude, prev_lon, prev_lat) / 1000) / nullIf(dateDiff('hour', prev_ts, event_ts), 0) as km_per_hour
FROM device_locations
WHERE prev_ts IS NOT NULL
  AND geoDistance(geo_longitude, geo_latitude, prev_lon, prev_lat) > 100000  -- > 100km
  AND dateDiff('hour', prev_ts, event_ts) < 2  -- < 2 hours
ORDER BY distance_km DESC
LIMIT 100;


-- Test 4.5: Suspicious User-Agent Patterns
-- Target: < 2 seconds
-- Devices with rotating device characteristics
SELECT
    device_id,
    count() as total_requests,
    uniq(device_brand) as unique_brands,
    uniq(device_model) as unique_models,
    uniq(os_version) as unique_os_versions,
    uniq(screen_density) as unique_screen_densities,
    groupArray(DISTINCT device_brand) as brands_used
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING unique_brands > 1 OR unique_models > 2
ORDER BY unique_brands DESC, unique_models DESC
LIMIT 100;


-- Test 4.6: Abnormal Request Volume Detection
-- Target: < 3 seconds
-- Devices with sudden spikes in activity
WITH daily_activity AS (
    SELECT
        device_id,
        event_date,
        count() as daily_requests
    FROM device360.ad_requests
    WHERE event_date >= today() - 30
    GROUP BY device_id, event_date
),
device_stats AS (
    SELECT
        device_id,
        event_date,
        daily_requests,
        avg(daily_requests) OVER (PARTITION BY device_id) as avg_daily,
        stddevPop(daily_requests) OVER (PARTITION BY device_id) as stddev_daily
    FROM daily_activity
)
SELECT
    device_id,
    event_date,
    daily_requests,
    avg_daily,
    (daily_requests - avg_daily) / nullIf(stddev_daily, 0) as z_score
FROM device_stats
WHERE stddev_daily > 0
  AND abs((daily_requests - avg_daily) / stddev_daily) > 3  -- 3 standard deviations
ORDER BY abs(z_score) DESC
LIMIT 100;


-- Test 4.7: 24/7 Activity Pattern Detection
-- Target: < 3 seconds
-- Real users sleep, bots don't
WITH hourly_activity AS (
    SELECT
        device_id,
        event_hour,
        count() as requests
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    GROUP BY device_id, event_hour
)
SELECT
    device_id,
    count(DISTINCT event_hour) as active_hours,
    sum(requests) as total_requests,
    avg(requests) as avg_requests_per_hour,
    stddevPop(requests) as stddev_requests
FROM hourly_activity
GROUP BY device_id
HAVING active_hours >= 22  -- Active in 22+ hours per day
ORDER BY total_requests DESC
LIMIT 100;


-- Test 4.8: Low Engagement / High Volume
-- Target: < 3 seconds
-- Many requests but minimal interaction time
SELECT
    device_id,
    count() as total_requests,
    avg(response_latency_ms) as avg_latency,
    sum(response_size_bytes) / 1024 / 1024 as total_mb,
    dateDiff('hour', min(event_ts), max(event_ts)) as active_hours,
    total_requests / nullIf(active_hours, 0) as requests_per_hour
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING total_requests > 1000
   AND avg_latency < 50  -- Suspiciously fast responses
   AND requests_per_hour > 100
ORDER BY requests_per_hour DESC
LIMIT 100;


-- Test 4.9: Fraud Score Correlation
-- Target: < 2 seconds
-- Analyze correlation between fraud scores and behavior
SELECT
    multiIf(
        greatest(fraud_score_ifa, fraud_score_ip) < 30, 'Low Risk',
        greatest(fraud_score_ifa, fraud_score_ip) < 60, 'Medium Risk',
        'High Risk'
    ) as risk_level,
    count() as requests,
    uniq(device_id) as unique_devices,
    avg(count()) OVER () / count() as relative_volume,
    avg(final_cpm) as avg_cpm
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY risk_level
ORDER BY
    CASE risk_level
        WHEN 'Low Risk' THEN 1
        WHEN 'Medium Risk' THEN 2
        ELSE 3
    END;


-- Test 4.10: Comprehensive Bot Score
-- Target: < 5 seconds
-- Calculate composite bot score using multiple signals
WITH device_signals AS (
    SELECT
        device_id,
        count() as total_requests,
        uniq(device_ip) as ip_count,
        uniq(geo_country) as country_count,
        uniq(device_brand) as brand_count,
        avg(fraud_score_ifa) as avg_fraud_ifa,
        avg(fraud_score_ip) as avg_fraud_ip,
        dateDiff('hour', min(event_ts), max(event_ts)) as active_hours,
        count(DISTINCT event_hour) as distinct_hours_active
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    GROUP BY device_id
    HAVING total_requests > 100
)
SELECT
    device_id,
    total_requests,
    -- Composite bot score (0-100)
    CAST(
        (
            -- High request volume (25 points)
            least(total_requests / 1000 * 25, 25) +
            -- Multiple IPs (25 points)
            least(ip_count / 10 * 25, 25) +
            -- Multiple countries (20 points)
            least(country_count / 5 * 20, 20) +
            -- Fraud scores (20 points)
            least(greatest(avg_fraud_ifa, avg_fraud_ip) / 5, 20) +
            -- 24/7 activity (10 points)
            if(distinct_hours_active >= 20, 10, 0)
        ) as UInt8
    ) as bot_score,
    ip_count,
    country_count,
    brand_count,
    avg_fraud_ifa,
    active_hours,
    distinct_hours_active
FROM device_signals
WHERE bot_score >= 50  -- High bot probability
ORDER BY bot_score DESC, total_requests DESC
LIMIT 500;


-- Test 4.11: Network Type Analysis
-- Target: < 2 seconds
-- Analyze bot distribution across network types
SELECT
    network_type,
    count() as requests,
    uniq(device_id) as unique_devices,
    avg(fraud_score_ifa) as avg_fraud_score,
    count() * 100.0 / sum(count()) OVER () as percentage
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY network_type
ORDER BY requests DESC;


-- Test 4.12: Bot Blocklist Export
-- Target: < 3 seconds
-- Generate list of devices to block
SELECT
    device_id,
    count() as requests,
    uniq(device_ip) as ips,
    uniq(geo_country) as countries,
    max(greatest(fraud_score_ifa, fraud_score_ip)) as max_fraud_score,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING requests > 1000
   AND (ips > 10 OR max_fraud_score > 70 OR countries > 5)
ORDER BY requests DESC
FORMAT CSV;
