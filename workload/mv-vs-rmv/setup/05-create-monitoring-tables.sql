-- ============================================================================
-- MV vs RMV 테스트: Monitoring Tables 생성
-- MV vs RMV Test: Monitoring Tables Creation
-- ============================================================================

-- 테스트 세션 관리 테이블
CREATE TABLE IF NOT EXISTS mv_vs_rmv.test_sessions
(
    session_id UUID DEFAULT generateUUIDv4(),
    test_type Enum8('MV_TEST' = 1, 'RMV_TEST' = 2, 'BOTH_TEST' = 3),
    start_time DateTime64(3) DEFAULT now64(3),
    end_time Nullable(DateTime64(3)),
    description String,
    config_json String DEFAULT '{}'
)
ENGINE = MergeTree()
ORDER BY (start_time, session_id)
COMMENT 'Test session management table';

-- 리소스 메트릭 스냅샷 (1분마다 수집)
CREATE TABLE IF NOT EXISTS mv_vs_rmv.resource_metrics
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,

    -- Query 메트릭
    query_count UInt64,
    query_duration_ms UInt64,

    -- Memory 메트릭
    memory_usage_bytes UInt64,
    peak_memory_usage_bytes UInt64,

    -- CPU/Processing 메트릭
    read_rows UInt64,
    read_bytes UInt64,
    written_rows UInt64,
    written_bytes UInt64,

    -- Merge 관련
    merge_count UInt64,
    parts_count UInt64,

    -- MV/RMV 별 구분
    metric_source Enum8('MV' = 1, 'RMV' = 2, 'SOURCE' = 3, 'SYSTEM' = 4)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, collected_at, metric_source)
COMMENT 'Resource metrics collected every minute';

-- Part 변화 추적
CREATE TABLE IF NOT EXISTS mv_vs_rmv.parts_history
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,
    table_name String,
    partition String,
    part_count UInt64,
    row_count UInt64,
    bytes_on_disk UInt64,
    active_parts UInt64,
    inactive_parts UInt64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, table_name, collected_at)
COMMENT 'Part count and size tracking over time';

-- Merge 활동 로그
CREATE TABLE IF NOT EXISTS mv_vs_rmv.merge_activity
(
    collected_at DateTime64(3) DEFAULT now64(3),
    session_id UUID,
    table_name String,
    event_type String,
    merge_duration_ms UInt64,
    rows_read UInt64,
    rows_written UInt64,
    bytes_read UInt64,
    bytes_written UInt64,
    memory_usage UInt64
)
ENGINE = MergeTree()
PARTITION BY toYYYYMMDD(collected_at)
ORDER BY (session_id, table_name, collected_at)
COMMENT 'Merge activity log for analysis';

-- 테이블 목록 확인
SELECT
    name,
    engine,
    total_rows,
    total_bytes,
    comment
FROM system.tables
WHERE database = 'mv_vs_rmv'
ORDER BY name
FORMAT Pretty;

SELECT 'Monitoring tables created successfully' AS status;
