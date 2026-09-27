-- ========================================
-- Phase 1: Device Journey Analysis Queries
-- Core use case for Device360 pattern
-- ========================================

-- Test 1.1: Single Device Point Lookup
-- Target: < 100ms
-- Retrieves all events for a specific device
SELECT *
FROM device360.ad_requests
WHERE device_id = 'e68bfaae-4981-4f64-b67b-0108daa2f896'
ORDER BY event_ts DESC
LIMIT 1000;


-- Test 1.2: Device Journey Timeline
-- Target: < 500ms
-- Reconstructs complete journey with temporal gaps
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
ORDER BY event_ts;


-- Test 1.3: Session Detection per Device
-- Target: < 1 second
-- Defines sessions by 30-minute inactivity gaps
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
ORDER BY event_ts;


-- Test 1.4: Device Session Summary
-- Target: < 1 second
-- Aggregates session-level metrics
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
ORDER BY session_start;


-- Test 1.5: Cross-App Journey (Funnel Analysis)
-- Target: < 500ms
-- Tracks sequence of apps a device interacts with
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
GROUP BY device_id;


-- Test 1.6: Location Journey Analysis
-- Target: < 1 second
-- Detects impossible travel patterns (bot indicator)
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
ORDER BY event_ts;


-- Test 1.7: Device Behavior Change Detection
-- Target: < 1 second
-- Identifies sudden behavioral changes (account takeover indicator)
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
ORDER BY event_date;


-- Test 1.8: First/Last Touch Attribution
-- Target: < 500ms
-- Device lifecycle analysis
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
GROUP BY device_id;


-- Test 1.9: Multi-Device Pattern Analysis
-- Compare behavior across multiple high-frequency devices
SELECT
    device_id,
    count() as total_requests,
    uniq(app_id) as unique_apps,
    uniq(device_ip) as unique_ips,
    uniq(geo_country) as unique_countries,
    min(event_ts) as first_seen,
    max(event_ts) as last_seen,
    dateDiff('hour', min(event_ts), max(event_ts)) as active_hours,
    count() / dateDiff('hour', min(event_ts), max(event_ts)) as requests_per_hour
FROM device360.ad_requests
WHERE event_date >= today() - 7
GROUP BY device_id
HAVING total_requests > 1000
ORDER BY total_requests DESC
LIMIT 20;


-- Test 1.10: Hourly Activity Pattern
-- Detect unnatural activity patterns (24/7 activity = bot)
SELECT
    device_id,
    event_hour,
    count() as requests_in_hour,
    avg(count()) OVER (PARTITION BY device_id) as avg_hourly_requests
FROM device360.ad_requests
WHERE device_id IN (
    SELECT device_id
    FROM device360.ad_requests
    WHERE event_date >= today() - 7
    GROUP BY device_id
    HAVING count() > 1000
    LIMIT 10
)
AND event_date >= today() - 7
GROUP BY device_id, event_hour
ORDER BY device_id, event_hour;
