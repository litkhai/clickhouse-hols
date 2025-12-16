-- ============================================================================
-- MV vs RMV 테스트: Materialized View (MV) 테이블 생성
-- MV vs RMV Test: Materialized View (MV) Table Creation
-- ============================================================================

-- MV용 Target Table (SummingMergeTree 사용)
CREATE TABLE IF NOT EXISTS mv_vs_rmv.events_agg_mv
(
    event_time_5min DateTime,
    event_type LowCardinality(String),
    country LowCardinality(String),
    device_type LowCardinality(String),
    event_count UInt64,
    unique_users UInt64,
    total_revenue Decimal(18,2),
    total_quantity UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMMDD(event_time_5min)
ORDER BY (event_time_5min, event_type, country, device_type)
COMMENT 'Target table for Materialized View - aggregated data with SummingMergeTree';

-- Materialized View (실시간 트리거)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_vs_rmv.events_mv_realtime
TO mv_vs_rmv.events_agg_mv
AS SELECT
    toStartOfFiveMinutes(event_time) AS event_time_5min,
    event_type,
    country,
    device_type,
    count() AS event_count,
    uniqExact(user_id) AS unique_users,
    sum(revenue) AS total_revenue,
    sum(quantity) AS total_quantity
FROM mv_vs_rmv.events_source
GROUP BY event_time_5min, event_type, country, device_type;

-- 테이블 정보 확인
DESCRIBE TABLE mv_vs_rmv.events_agg_mv;

-- MV 정보 확인
SELECT
    database,
    name,
    engine,
    create_table_query
FROM system.tables
WHERE database = 'mv_vs_rmv'
  AND name = 'events_mv_realtime'
FORMAT Vertical;

SELECT 'MV tables created successfully' AS status;
