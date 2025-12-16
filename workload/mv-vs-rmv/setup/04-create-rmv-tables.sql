-- ============================================================================
-- MV vs RMV 테스트: Refreshable Materialized View (RMV) 테이블 생성
-- MV vs RMV Test: Refreshable Materialized View (RMV) Table Creation
-- ============================================================================

-- RMV용 Target Table
CREATE TABLE IF NOT EXISTS mv_vs_rmv.events_agg_rmv
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
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time_5min)
ORDER BY (event_time_5min, event_type, country, device_type)
COMMENT 'Target table for Refreshable Materialized View - aggregated data with MergeTree';

-- Refreshable Materialized View (5분 주기 배치)
-- APPEND 모드: 새로운 데이터만 추가
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_vs_rmv.events_rmv_batch
REFRESH EVERY 5 MINUTE APPEND
TO mv_vs_rmv.events_agg_rmv
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
WHERE event_time >= now() - INTERVAL 6 MINUTE  -- 겹침 방지 + 안전 마진
  AND event_time < now() - INTERVAL 1 MINUTE   -- 최신 데이터 제외 (아직 완전히 쌓이지 않은 데이터)
GROUP BY event_time_5min, event_type, country, device_type;

-- 테이블 정보 확인
DESCRIBE TABLE mv_vs_rmv.events_agg_rmv;

-- RMV 정보 확인
SELECT
    database,
    name,
    engine,
    create_table_query
FROM system.tables
WHERE database = 'mv_vs_rmv'
  AND name = 'events_rmv_batch'
FORMAT Vertical;

-- RMV refresh 상태 확인
SELECT
    database,
    view,
    status,
    last_success_time,
    last_refresh_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'mv_vs_rmv'
  AND view = 'events_rmv_batch'
FORMAT Vertical;

SELECT 'RMV tables created successfully' AS status;
