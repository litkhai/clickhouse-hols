-- Main Events Table: ad_requests
-- Optimized for Device360 query patterns with device_id-first ordering

CREATE TABLE IF NOT EXISTS device360.ad_requests
(
    -- Temporal dimensions
    event_ts DateTime,
    event_date Date,
    event_hour UInt8,

    -- Device identifiers (PRIMARY in ORDER BY)
    device_id String,
    device_ip String,
    device_brand LowCardinality(String),
    device_model LowCardinality(String),
    os_version UInt16,
    platform_type UInt8,

    -- Geographic dimensions
    geo_country LowCardinality(String),
    geo_region LowCardinality(String),
    geo_city LowCardinality(String),
    geo_continent LowCardinality(String),
    geo_longitude Float32,
    geo_latitude Float32,

    -- Application context
    app_id String,
    app_bundle String,
    app_name LowCardinality(String),
    app_category LowCardinality(String),

    -- Request metrics
    ad_type UInt8,
    bid_floor Float32,
    final_cpm Float32,
    response_latency_ms UInt16,
    response_size_bytes UInt32,

    -- Bot detection signals
    fraud_score_ifa UInt8,
    fraud_score_ip UInt8,
    network_type UInt8,
    screen_density UInt16,
    tracking_consent LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (device_id, event_date, event_ts)
SETTINGS index_granularity = 8192;

-- Critical design decision: device_id comes FIRST in ORDER BY
-- This enables millisecond-level point lookups for individual device queries
-- Unlike typical time-series designs, Device360 patterns prioritize device-level access
