-- ClickHouse 25.6 Feature: Time and Time64 Data Types
-- Purpose: Test the new Time and Time64 data types for time-of-day representation
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06

-- Drop tables if exist
DROP TABLE IF EXISTS business_hours;
DROP TABLE IF EXISTS performance_metrics;

-- Create a table using Time data type
-- Time represents time-of-day without date, stored as seconds since midnight
CREATE TABLE business_hours
(
    location String,
    day_of_week String,
    opening_time Time,     -- Time data type (seconds precision)
    closing_time Time,
    lunch_start Time,
    lunch_end Time
)
ENGINE = MergeTree()
ORDER BY (location, day_of_week);

-- Insert business hours data
-- Time values can be specified as 'HH:MM:SS' strings
INSERT INTO business_hours VALUES
    ('New York', 'Monday', '09:00:00', '18:00:00', '12:00:00', '13:00:00'),
    ('New York', 'Tuesday', '09:00:00', '18:00:00', '12:00:00', '13:00:00'),
    ('New York', 'Friday', '09:00:00', '17:00:00', '12:00:00', '13:00:00'),
    ('London', 'Monday', '08:30:00', '17:30:00', '12:30:00', '13:30:00'),
    ('London', 'Tuesday', '08:30:00', '17:30:00', '12:30:00', '13:30:00'),
    ('Tokyo', 'Monday', '09:00:00', '18:00:00', '12:00:00', '13:00:00'),
    ('Tokyo', 'Tuesday', '09:00:00', '18:00:00', '12:00:00', '13:00:00');

-- Query 1: View business hours
SELECT '=== Business Hours Schedule ===' AS title;
SELECT * FROM business_hours ORDER BY location, day_of_week;

-- Query 2: Calculate working hours per day
SELECT '=== Working Hours Per Day ===' AS title;
SELECT
    location,
    day_of_week,
    opening_time,
    closing_time,
    closing_time - opening_time AS total_seconds,
    formatReadableTimeDelta(closing_time - opening_time) AS total_hours
FROM business_hours
ORDER BY location, day_of_week;

-- Query 3: Calculate actual working time (excluding lunch)
SELECT '=== Actual Working Time (Excluding Lunch) ===' AS title;
SELECT
    location,
    day_of_week,
    (closing_time - opening_time) - (lunch_end - lunch_start) AS work_seconds,
    formatReadableTimeDelta((closing_time - opening_time) - (lunch_end - lunch_start)) AS work_hours
FROM business_hours
ORDER BY location, day_of_week;

-- Query 4: Check if a specific time is within business hours
SELECT '=== Is 14:30:00 Within Business Hours? ===' AS title;
SELECT
    location,
    day_of_week,
    opening_time,
    closing_time,
    '14:30:00'::Time AS check_time,
    CASE
        WHEN '14:30:00'::Time >= opening_time AND '14:30:00'::Time <= closing_time
            AND NOT ('14:30:00'::Time >= lunch_start AND '14:30:00'::Time < lunch_end)
        THEN 'OPEN'
        WHEN '14:30:00'::Time >= lunch_start AND '14:30:00'::Time < lunch_end
        THEN 'LUNCH BREAK'
        ELSE 'CLOSED'
    END AS status
FROM business_hours
WHERE day_of_week = 'Monday'
ORDER BY location;

-- Create a table using Time64 data type for high-precision timing
-- Time64 supports microsecond precision for performance monitoring
CREATE TABLE performance_metrics
(
    request_id UInt64,
    endpoint String,
    start_time Time64(6),    -- Microsecond precision
    end_time Time64(6),
    status_code UInt16
)
ENGINE = MergeTree()
ORDER BY request_id;

-- Insert performance metrics with microsecond precision
INSERT INTO performance_metrics VALUES
    (1, '/api/users', '10:30:15.123456'::Time64(6), '10:30:15.145678'::Time64(6), 200),
    (2, '/api/orders', '10:30:16.234567'::Time64(6), '10:30:16.356789'::Time64(6), 200),
    (3, '/api/products', '10:30:17.345678'::Time64(6), '10:30:17.987654'::Time64(6), 200),
    (4, '/api/users', '10:30:18.456789'::Time64(6), '10:30:18.567890'::Time64(6), 200),
    (5, '/api/checkout', '10:30:19.567890'::Time64(6), '10:30:20.123456'::Time64(6), 200);

-- Query 5: View performance metrics
SELECT '=== Performance Metrics ===' AS title;
SELECT * FROM performance_metrics ORDER BY request_id;

-- Query 6: Calculate response times in microseconds
SELECT '=== Response Time Analysis ===' AS title;
SELECT
    request_id,
    endpoint,
    start_time,
    end_time,
    (end_time - start_time) AS response_microseconds,
    round((end_time - start_time) / 1000000, 3) AS response_seconds
FROM performance_metrics
ORDER BY response_microseconds DESC;

-- Query 7: Aggregate statistics per endpoint
SELECT '=== Endpoint Performance Statistics ===' AS title;
SELECT
    endpoint,
    count() AS request_count,
    round(avg(end_time - start_time) / 1000000, 6) AS avg_response_sec,
    round(min(end_time - start_time) / 1000000, 6) AS min_response_sec,
    round(max(end_time - start_time) / 1000000, 6) AS max_response_sec,
    round(quantile(0.95)((end_time - start_time) / 1000000), 6) AS p95_response_sec
FROM performance_metrics
GROUP BY endpoint
ORDER BY avg_response_sec DESC;

-- Real-world use case: Shift scheduling
DROP TABLE IF EXISTS employee_shifts;

CREATE TABLE employee_shifts
(
    employee_id UInt32,
    employee_name String,
    shift_date Date,
    shift_start Time,
    shift_end Time,
    break_start Time,
    break_end Time
)
ENGINE = MergeTree()
ORDER BY (shift_date, employee_id);

-- Insert shift schedules
INSERT INTO employee_shifts VALUES
    (101, 'Alice Johnson', '2025-01-15', '08:00:00', '16:00:00', '12:00:00', '12:30:00'),
    (102, 'Bob Smith', '2025-01-15', '09:00:00', '17:00:00', '12:30:00', '13:00:00'),
    (103, 'Carol White', '2025-01-15', '14:00:00', '22:00:00', '18:00:00', '18:30:00'),
    (101, 'Alice Johnson', '2025-01-16', '08:00:00', '16:00:00', '12:00:00', '12:30:00'),
    (104, 'David Brown', '2025-01-16', '06:00:00', '14:00:00', '10:00:00', '10:30:00');

-- Query 8: Shift schedule overview
SELECT '=== Employee Shift Schedule ===' AS title;
SELECT
    shift_date,
    employee_name,
    shift_start,
    shift_end,
    formatReadableTimeDelta(shift_end - shift_start) AS shift_duration,
    formatReadableTimeDelta((shift_end - shift_start) - (break_end - break_start)) AS working_hours
FROM employee_shifts
ORDER BY shift_date, shift_start;

-- Query 9: Calculate overtime (shifts longer than 8 hours)
SELECT '=== Overtime Analysis ===' AS title;
SELECT
    employee_name,
    shift_date,
    shift_start,
    shift_end,
    (shift_end - shift_start - (break_end - break_start)) AS work_seconds,
    formatReadableTimeDelta(shift_end - shift_start - (break_end - break_start)) AS work_hours,
    CASE
        WHEN (shift_end - shift_start - (break_end - break_start)) > 8*3600
        THEN 'OVERTIME'
        ELSE 'REGULAR'
    END AS shift_type
FROM employee_shifts
ORDER BY shift_date, employee_id;

-- Query 10: Check for shift overlaps
SELECT '=== Shift Coverage Timeline ===' AS title;
SELECT
    shift_date,
    shift_start AS time_point,
    employee_name,
    'SHIFT START' AS event_type
FROM employee_shifts
UNION ALL
SELECT
    shift_date,
    shift_end AS time_point,
    employee_name,
    'SHIFT END' AS event_type
FROM employee_shifts
ORDER BY shift_date, time_point, event_type;

-- Time arithmetic examples
SELECT '=== Time Arithmetic Examples ===' AS title;
SELECT
    '10:30:00'::Time AS base_time,
    '10:30:00'::Time + 3600 AS add_1_hour,
    '10:30:00'::Time - 1800 AS subtract_30_min,
    '14:30:00'::Time - '10:30:00'::Time AS time_difference_seconds,
    formatReadableTimeDelta('14:30:00'::Time - '10:30:00'::Time) AS time_difference_readable;

-- Benefits of Time and Time64 data types
SELECT '=== Time/Time64 Data Type Benefits ===' AS info;
SELECT
    'Efficient storage for time-of-day values without date' AS benefit_1,
    'Natural representation of business hours and schedules' AS benefit_2,
    'Time64 provides microsecond precision for performance metrics' AS benefit_3,
    'Simple arithmetic operations on time values' AS benefit_4,
    'Better type safety compared to storing seconds as integers' AS benefit_5;

-- Use cases
SELECT '=== Common Use Cases ===' AS info;
SELECT
    'Business hours and operating schedules' AS use_case_1,
    'Employee shift management' AS use_case_2,
    'API performance monitoring with microsecond precision' AS use_case_3,
    'Service availability and SLA tracking' AS use_case_4,
    'Time-based access control and scheduling' AS use_case_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE business_hours;
-- DROP TABLE performance_metrics;
-- DROP TABLE employee_shifts;

SELECT '✅ Time and Time64 Data Types Test Complete!' AS status;
