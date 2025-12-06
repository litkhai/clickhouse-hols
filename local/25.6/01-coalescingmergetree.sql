-- ClickHouse 25.6 Feature: CoalescingMergeTree Table Engine
-- Purpose: Test the CoalescingMergeTree engine optimized for sparse updates
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06

-- Drop table if exists
DROP TABLE IF EXISTS metrics_coalescing;

-- Create a table with CoalescingMergeTree engine
-- CoalescingMergeTree is designed for tables with sparse updates
-- It automatically coalesces rows during merges based on Sign column
CREATE TABLE metrics_coalescing
(
    metric_id UInt32,
    timestamp DateTime,
    value Float64,
    Sign Int8  -- Sign column: 1 for insert, -1 for delete/update (old value)
)
ENGINE = CoalescingMergeTree(Sign)
ORDER BY (metric_id, timestamp)
SETTINGS index_granularity = 8192;

-- Insert initial metrics data
INSERT INTO metrics_coalescing VALUES
    (1, '2025-01-01 00:00:00', 100.0, 1),
    (2, '2025-01-01 00:00:00', 200.0, 1),
    (3, '2025-01-01 00:00:00', 300.0, 1);

-- Query 1: View initial data
SELECT '=== Initial Metrics ===' AS title;
SELECT * FROM metrics_coalescing ORDER BY metric_id, timestamp;

-- Simulate an update by inserting the old value with Sign=-1 and new value with Sign=1
-- Update metric_id=1 from 100.0 to 150.0
INSERT INTO metrics_coalescing VALUES
    (1, '2025-01-01 00:00:00', 100.0, -1),  -- Cancel old value
    (1, '2025-01-01 00:00:00', 150.0, 1);   -- Insert new value

-- Query 2: View data after update (before merge)
SELECT '=== After Update (Before Merge) ===' AS title;
SELECT * FROM metrics_coalescing ORDER BY metric_id, timestamp;

-- Query 3: Sum with Sign to get effective values
SELECT '=== Effective Values (Sign-Weighted Sum) ===' AS title;
SELECT
    metric_id,
    timestamp,
    sum(value * Sign) AS effective_value
FROM metrics_coalescing
GROUP BY metric_id, timestamp
ORDER BY metric_id;

-- Insert more updates to demonstrate coalescing behavior
INSERT INTO metrics_coalescing VALUES
    -- Update metric_id=2
    (2, '2025-01-01 00:00:00', 200.0, -1),
    (2, '2025-01-01 00:00:00', 250.0, 1),
    -- Add new timestamp for metric_id=1
    (1, '2025-01-01 01:00:00', 160.0, 1),
    -- Delete metric_id=3
    (3, '2025-01-01 00:00:00', 300.0, -1);

-- Query 4: View all data with multiple updates
SELECT '=== All Data with Multiple Updates ===' AS title;
SELECT * FROM metrics_coalescing ORDER BY metric_id, timestamp, Sign;

-- Query 5: Get current effective values (final state)
SELECT '=== Current Effective Values ===' AS title;
SELECT
    metric_id,
    timestamp,
    sum(value * Sign) AS effective_value,
    sum(Sign) AS sign_sum,
    CASE
        WHEN sum(Sign) = 0 THEN 'DELETED'
        WHEN sum(Sign) > 0 THEN 'ACTIVE'
        ELSE 'ERROR'
    END AS status
FROM metrics_coalescing
GROUP BY metric_id, timestamp
HAVING sum(Sign) != 0  -- Filter out deleted records
ORDER BY metric_id, timestamp;

-- Real-world use case: Tracking sensor metrics with updates
DROP TABLE IF EXISTS sensor_metrics;

CREATE TABLE sensor_metrics
(
    sensor_id String,
    reading_time DateTime,
    temperature Float32,
    humidity Float32,
    location String,
    Sign Int8
)
ENGINE = CoalescingMergeTree(Sign)
ORDER BY (sensor_id, reading_time)
PARTITION BY toYYYYMM(reading_time);

-- Insert initial sensor readings
INSERT INTO sensor_metrics VALUES
    ('SENSOR-001', '2025-01-01 10:00:00', 22.5, 45.0, 'Room-A', 1),
    ('SENSOR-002', '2025-01-01 10:00:00', 23.0, 50.0, 'Room-B', 1),
    ('SENSOR-003', '2025-01-01 10:00:00', 21.5, 48.0, 'Room-C', 1);

-- Query 6: Initial sensor readings
SELECT '=== Initial Sensor Readings ===' AS title;
SELECT
    sensor_id,
    reading_time,
    temperature,
    humidity,
    location
FROM sensor_metrics
WHERE Sign = 1
ORDER BY sensor_id;

-- Correct a sensor reading (was recorded with wrong location)
INSERT INTO sensor_metrics VALUES
    ('SENSOR-001', '2025-01-01 10:00:00', 22.5, 45.0, 'Room-A', -1),
    ('SENSOR-001', '2025-01-01 10:00:00', 22.5, 45.0, 'Room-D', 1);

-- Query 7: Corrected sensor reading
SELECT '=== After Location Correction ===' AS title;
SELECT
    sensor_id,
    reading_time,
    temperature,
    humidity,
    location,
    sum(Sign) as record_count
FROM sensor_metrics
GROUP BY sensor_id, reading_time, temperature, humidity, location
HAVING sum(Sign) > 0
ORDER BY sensor_id;

-- Query 8: Time series with latest values
INSERT INTO sensor_metrics VALUES
    ('SENSOR-001', '2025-01-01 11:00:00', 23.0, 46.0, 'Room-D', 1),
    ('SENSOR-002', '2025-01-01 11:00:00', 23.5, 51.0, 'Room-B', 1),
    ('SENSOR-003', '2025-01-01 11:00:00', 22.0, 49.0, 'Room-C', 1);

SELECT '=== Time Series Data ===' AS title;
SELECT
    sensor_id,
    reading_time,
    temperature,
    humidity,
    location
FROM sensor_metrics
WHERE Sign = 1
ORDER BY sensor_id, reading_time;

-- Query 9: Latest reading per sensor
SELECT '=== Latest Reading Per Sensor ===' AS title;
SELECT
    sensor_id,
    argMax(temperature, reading_time) as latest_temp,
    argMax(humidity, reading_time) as latest_humidity,
    argMax(location, reading_time) as current_location,
    max(reading_time) as last_update
FROM sensor_metrics
WHERE Sign = 1
GROUP BY sensor_id
ORDER BY sensor_id;

-- Benefits of CoalescingMergeTree
SELECT '=== CoalescingMergeTree Benefits ===' AS info;
SELECT
    'Automatic coalescing during merges reduces storage' AS benefit_1,
    'Efficient handling of sparse updates without full rewrites' AS benefit_2,
    'Sign column enables update/delete semantics on immutable storage' AS benefit_3,
    'Better performance than ReplacingMergeTree for frequent updates' AS benefit_4,
    'Ideal for metrics, sensors, and real-time tracking use cases' AS benefit_5;

-- Performance comparison note
SELECT '=== Use Cases ===' AS info;
SELECT
    'Metrics and monitoring systems' AS use_case_1,
    'Sensor data with corrections' AS use_case_2,
    'User state tracking' AS use_case_3,
    'Real-time dashboards with updates' AS use_case_4,
    'Change data capture (CDC) scenarios' AS use_case_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE sensor_metrics;
-- DROP TABLE metrics_coalescing;

SELECT '✅ CoalescingMergeTree Test Complete!' AS status;
