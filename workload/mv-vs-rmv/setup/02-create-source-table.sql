-- ============================================================================
-- MV vs RMV 테스트: Source Table 생성
-- MV vs RMV Test: Source Table Creation
-- ============================================================================

-- Source Table 생성
CREATE TABLE IF NOT EXISTS mv_vs_rmv.events_source
(
    event_time DateTime64(3) DEFAULT now64(3),
    user_id UInt32,
    event_type LowCardinality(String),
    page_url String,
    session_id UUID,
    country LowCardinality(String),
    device_type LowCardinality(String),
    revenue Decimal(10,2),
    quantity UInt16
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (event_type, user_id, event_time)
COMMENT 'Source table for MV vs RMV test - receives continuous inserts';

-- 테이블 정보 확인
DESCRIBE TABLE mv_vs_rmv.events_source;

-- 테이블 생성 쿼리 확인
SHOW CREATE TABLE mv_vs_rmv.events_source;

SELECT 'Source table events_source created successfully' AS status;
