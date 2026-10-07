-- Benchmark Events Table: ad_requests (12 columns)
-- The shape used by the December 2025 benchmark run (4.48B rows).
-- Written by scripts/generate_with_persistence.py, queried by
-- scripts/run_query_benchmark.sh and scripts/comprehensive_query_benchmark.sh.
-- scripts/ec2_generate_and_upload.py writes these 12 fields plus 21 more; with the
-- default input_format_skip_unknown_fields = 1 the extra fields are dropped on insert.
--
-- This table shares the name device360.ad_requests with 02_create_main_table.sql
-- (the 29-column query-suite shape). Use one or the other in a database, not both.

CREATE TABLE IF NOT EXISTS device360.ad_requests
(
    event_ts DateTime,
    event_date Date,
    event_hour UInt8,
    device_id String,
    device_ip String,
    device_brand LowCardinality(String),
    device_model LowCardinality(String),
    app_name LowCardinality(String),
    country LowCardinality(String),
    city LowCardinality(String),
    click UInt8,
    impression_id String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (device_id, event_date, event_ts)
SETTINGS index_granularity = 8192;

-- device_id comes FIRST in ORDER BY: all events of one device are co-located,
-- which is what makes the single-device point lookups fast.
