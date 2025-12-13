-- Create Kafka source table
-- Note: Kafka Engine doesn't support DEFAULT expressions
CREATE TABLE IF NOT EXISTS default.kafka_events (
    event_time DateTime,
    query_kind String,
    query_duration_ms UInt32
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'test-events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1;

-- Create buffer table for Kafka data
CREATE TABLE IF NOT EXISTS default.events_buffer (
    event_time DateTime,
    query_kind String,
    query_duration_ms UInt32
) ENGINE = MergeTree()
ORDER BY (event_time, query_kind);

-- Create MySQL table engine
CREATE TABLE IF NOT EXISTS default.mysql_aggregated_events (
    event_date Date,
    query_kind String,
    query_count UInt64,
    total_duration_ms UInt64
) ENGINE = MySQL('mysql:3306', 'testdb', 'aggregated_events', 'clickhouse', 'clickhouse');

-- Create materialized view: Kafka -> Buffer
CREATE MATERIALIZED VIEW IF NOT EXISTS default.kafka_to_buffer_mv
TO default.events_buffer
AS
SELECT
    event_time,
    query_kind,
    query_duration_ms
FROM default.kafka_events;

-- Create materialized view with block size settings: Buffer -> MySQL
CREATE MATERIALIZED VIEW IF NOT EXISTS default.buffer_to_mysql_mv
TO default.mysql_aggregated_events
AS
SELECT
    toDate(event_time) AS event_date,
    query_kind,
    count() AS query_count,
    sum(query_duration_ms) AS total_duration_ms
FROM default.events_buffer
GROUP BY event_date, query_kind
SETTINGS
    max_block_size = 1000,
    min_insert_block_size_rows = 5000,
    min_insert_block_size_bytes = 268435456;
