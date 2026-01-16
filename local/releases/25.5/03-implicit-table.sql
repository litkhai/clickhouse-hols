-- ClickHouse 25.5 Feature: Implicit Table in clickhouse-local
-- Purpose: Demonstrate implicit table feature for simplified data exploration
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-05

-- Note: The implicit table feature is primarily designed for clickhouse-local with stdin
-- This script demonstrates the concepts and equivalent patterns in regular ClickHouse

SELECT '=== Implicit Table Feature Overview ===' AS title;
SELECT
    'ClickHouse 25.5 allows omitting FROM and SELECT clauses in clickhouse-local' AS feature,
    'Simplifies quick data exploration and schema inspection' AS benefit,
    'Works with streamed JSON data via stdin' AS input_method,
    'Uses functions like JSONAllPathsWithTypes() for automatic analysis' AS capability;

-- Create sample data to simulate stdin scenarios
DROP TABLE IF EXISTS streaming_events;

CREATE TABLE streaming_events
(
    event_id UInt64,
    event_type String,
    user_id UInt32,
    timestamp DateTime,
    properties String,  -- JSON string
    metadata String     -- JSON string
)
ENGINE = MergeTree()
ORDER BY (event_type, timestamp)
SETTINGS index_granularity = 8192;

-- Insert sample streaming event data
INSERT INTO streaming_events VALUES
    (1, 'page_view', 1001, '2025-01-15 10:00:00', '{"page":"/home","duration":45}', '{"browser":"Chrome","device":"desktop"}'),
    (2, 'click', 1001, '2025-01-15 10:00:45', '{"element":"button","label":"signup"}', '{"browser":"Chrome","device":"desktop"}'),
    (3, 'page_view', 1002, '2025-01-15 10:01:00', '{"page":"/products","duration":120}', '{"browser":"Firefox","device":"mobile"}'),
    (4, 'purchase', 1002, '2025-01-15 10:03:00', '{"product_id":"P123","amount":99.99}', '{"browser":"Firefox","device":"mobile"}'),
    (5, 'page_view', 1003, '2025-01-15 10:05:00', '{"page":"/about","duration":30}', '{"browser":"Safari","device":"tablet"}'),
    (6, 'click', 1003, '2025-01-15 10:05:30', '{"element":"link","label":"contact"}', '{"browser":"Safari","device":"tablet"}'),
    (7, 'purchase', 1001, '2025-01-15 10:10:00', '{"product_id":"P456","amount":149.99}', '{"browser":"Chrome","device":"desktop"}'),
    (8, 'page_view', 1004, '2025-01-15 10:15:00', '{"page":"/home","duration":60}', '{"browser":"Edge","device":"desktop"}'),
    (9, 'click', 1004, '2025-01-15 10:16:00', '{"element":"button","label":"learn_more"}', '{"browser":"Edge","device":"desktop"}'),
    (10, 'page_view', 1005, '2025-01-15 10:20:00', '{"page":"/pricing","duration":90}', '{"browser":"Chrome","device":"mobile"}');

-- Query 1: Analyze JSON structure using JSONAllPathsWithTypes()
-- This simulates the implicit table feature's schema discovery
SELECT '=== JSON Schema Discovery (JSONAllPathsWithTypes) ===' AS title;
SELECT DISTINCT
    JSONAllPathsWithTypes(properties) AS properties_schema
FROM streaming_events
LIMIT 5;

-- Query 2: Extract and analyze nested JSON properties
SELECT '=== Event Properties Analysis ===' AS title;
SELECT
    event_type,
    JSONExtractString(properties, 'page') AS page,
    JSONExtractString(properties, 'element') AS element,
    JSONExtractString(properties, 'product_id') AS product_id,
    JSONExtractFloat(properties, 'amount') AS amount,
    count(*) AS event_count
FROM streaming_events
GROUP BY event_type, page, element, product_id, amount
ORDER BY event_type, event_count DESC;

-- Query 3: Device and browser analysis from metadata
SELECT '=== Device and Browser Distribution ===' AS title;
SELECT
    JSONExtractString(metadata, 'browser') AS browser,
    JSONExtractString(metadata, 'device') AS device,
    count(*) AS session_count,
    uniq(user_id) AS unique_users
FROM streaming_events
GROUP BY browser, device
ORDER BY session_count DESC;

-- Query 4: User journey analysis
SELECT '=== User Journey Tracking ===' AS title;
SELECT
    user_id,
    groupArray(event_type) AS event_sequence,
    count(*) AS total_events,
    min(timestamp) AS session_start,
    max(timestamp) AS session_end,
    date_diff('second', min(timestamp), max(timestamp)) AS session_duration_sec
FROM streaming_events
GROUP BY user_id
ORDER BY user_id;

-- Real-world use case: Log analysis with automatic schema detection
DROP TABLE IF EXISTS application_logs;

CREATE TABLE application_logs
(
    log_id UInt64,
    timestamp DateTime,
    level String,
    service String,
    message String,
    context String  -- JSON context data
)
ENGINE = MergeTree()
ORDER BY (service, timestamp)
SETTINGS index_granularity = 8192;

-- Insert sample application logs
INSERT INTO application_logs VALUES
    (1, '2025-01-15 10:00:00', 'INFO', 'api-gateway', 'Request received', '{"endpoint":"/api/users","method":"GET","status":200,"latency_ms":45}'),
    (2, '2025-01-15 10:00:01', 'INFO', 'user-service', 'User lookup', '{"user_id":1001,"cache_hit":true,"latency_ms":5}'),
    (3, '2025-01-15 10:00:05', 'WARN', 'api-gateway', 'Slow request', '{"endpoint":"/api/orders","method":"POST","status":200,"latency_ms":1200}'),
    (4, '2025-01-15 10:00:10', 'ERROR', 'order-service', 'Database timeout', '{"query":"SELECT * FROM orders","timeout_ms":5000,"retry_count":3}'),
    (5, '2025-01-15 10:00:15', 'INFO', 'payment-service', 'Payment processed', '{"transaction_id":"TXN123","amount":99.99,"currency":"USD","status":"success"}'),
    (6, '2025-01-15 10:00:20', 'INFO', 'api-gateway', 'Request received', '{"endpoint":"/api/products","method":"GET","status":200,"latency_ms":30}'),
    (7, '2025-01-15 10:00:25', 'ERROR', 'inventory-service', 'Stock check failed', '{"product_id":"P456","error":"connection_refused","retry_count":2}'),
    (8, '2025-01-15 10:00:30', 'INFO', 'notification-service', 'Email sent', '{"recipient":"user@example.com","template":"order_confirmation","status":"delivered"}'),
    (9, '2025-01-15 10:00:35', 'WARN', 'api-gateway', 'Rate limit warning', '{"client_ip":"192.168.1.100","requests_per_minute":450,"threshold":500}'),
    (10, '2025-01-15 10:00:40', 'INFO', 'auth-service', 'User authenticated', '{"user_id":1005,"method":"oauth2","provider":"google"}');

-- Query 5: Discover all log context fields
SELECT '=== Log Context Schema Discovery ===' AS title;
SELECT DISTINCT
    service,
    JSONAllPathsWithTypes(context) AS context_schema
FROM application_logs;

-- Query 6: Service health dashboard
SELECT '=== Service Health Summary ===' AS title;
SELECT
    service,
    count(*) AS total_logs,
    countIf(level = 'ERROR') AS error_count,
    countIf(level = 'WARN') AS warning_count,
    countIf(level = 'INFO') AS info_count,
    round(avg(JSONExtractFloat(context, 'latency_ms')), 2) AS avg_latency_ms
FROM application_logs
GROUP BY service
ORDER BY error_count DESC, warning_count DESC;

-- Query 7: Error analysis with context
SELECT '=== Error Details ===' AS title;
SELECT
    timestamp,
    service,
    message,
    context
FROM application_logs
WHERE level = 'ERROR'
ORDER BY timestamp;

-- Query 8: API endpoint performance
SELECT '=== API Endpoint Performance ===' AS title;
SELECT
    JSONExtractString(context, 'endpoint') AS endpoint,
    JSONExtractString(context, 'method') AS method,
    count(*) AS request_count,
    avg(JSONExtractFloat(context, 'latency_ms')) AS avg_latency,
    max(JSONExtractFloat(context, 'latency_ms')) AS max_latency,
    countIf(JSONExtractInt(context, 'status') >= 400) AS error_count
FROM application_logs
WHERE service = 'api-gateway' AND context LIKE '%endpoint%'
GROUP BY endpoint, method
ORDER BY avg_latency DESC;

-- Benefits of implicit table feature
SELECT '=== Implicit Table Benefits ===' AS info;
SELECT
    'Omit FROM clause for quick stdin data exploration' AS benefit_1,
    'Automatic schema inference with JSONAllPathsWithTypes()' AS benefit_2,
    'Faster prototyping and data investigation' AS benefit_3,
    'Simplified clickhouse-local command line usage' AS benefit_4,
    'Perfect for ad-hoc log analysis and debugging' AS benefit_5;

-- Use cases for implicit table
SELECT '=== Use Cases ===' AS info;
SELECT
    'Quick JSON schema inspection from streaming sources' AS use_case_1,
    'Log file analysis without defining tables' AS use_case_2,
    'Data quality validation on incoming streams' AS use_case_3,
    'Rapid prototyping of data transformations' AS use_case_4,
    'Ad-hoc analysis of API responses' AS use_case_5,
    'Debugging production issues with log samples' AS use_case_6;

-- Example clickhouse-local commands (shown as reference)
SELECT '=== Example clickhouse-local Commands ===' AS info;
SELECT
    'echo ''{"key":"value"}'' | clickhouse-local --query "JSONAllPathsWithTypes(_)"' AS example_1,
    'cat data.json | clickhouse-local --query "SELECT count() FROM _"' AS example_2,
    'curl api.example.com | clickhouse-local --query "SELECT * FROM _"' AS example_3,
    'Use underscore (_) to reference implicit table in clickhouse-local' AS note;

-- Performance considerations
SELECT '=== Performance Tips ===' AS info;
SELECT
    'Use explicit schema when structure is known for better performance' AS tip_1,
    'JSONAllPathsWithTypes() is great for exploration, not production queries' AS tip_2,
    'Consider materialized columns for frequently accessed JSON fields' AS tip_3,
    'Use format inference settings for automatic type detection' AS tip_4,
    'Implicit table best for small to medium datasets in clickhouse-local' AS tip_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE application_logs;
-- DROP TABLE streaming_events;

SELECT '✅ Implicit Table Test Complete!' AS status;
SELECT 'Note: Full implicit table feature requires clickhouse-local with stdin' AS note;
