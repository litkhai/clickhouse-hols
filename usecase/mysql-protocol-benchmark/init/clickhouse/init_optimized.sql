-- ============================================================
-- ClickHouse 최적화된 스키마: Point Query 성능 극대화
-- ============================================================

CREATE DATABASE IF NOT EXISTS gamedb;

-- ============================================================
-- 1. 최적화된 MergeTree 테이블 (index_granularity = 256)
-- ============================================================

CREATE TABLE IF NOT EXISTS gamedb.player_last_login_optimized
(
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class LowCardinality(String),
    server_id UInt8,
    server_name LowCardinality(String),
    last_login_at DateTime64(3),
    last_logout_at Nullable(DateTime64(3)),
    last_ip IPv4,
    last_device_type LowCardinality(String),
    last_app_version LowCardinality(String),
    total_playtime_minutes UInt32,
    vip_level UInt8,
    guild_id Nullable(UInt64),
    guild_name Nullable(String),
    last_map_id UInt16,
    last_position_x Float32,
    last_position_y Float32,
    last_position_z Float32,
    currency_gold UInt64,
    currency_diamond UInt32,
    inventory_slots_used UInt16,
    created_at DateTime64(3) DEFAULT now64(3),
    updated_at DateTime64(3) DEFAULT now64(3),

    -- Bloom Filter Index
    INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS
    -- Point Query 최적화: index_granularity를 256으로 축소
    index_granularity = 256,
    index_granularity_bytes = 0,  -- Adaptive 비활성화
    -- 압축 최적화
    min_compress_block_size = 65536,
    max_compress_block_size = 1048576;

-- 기존 데이터 복사
INSERT INTO gamedb.player_last_login_optimized
SELECT * FROM gamedb.player_last_login;

-- 테이블 최적화
OPTIMIZE TABLE gamedb.player_last_login_optimized FINAL;


-- ============================================================
-- 2. Memory 엔진 테이블 (완전 인메모리)
-- ============================================================

CREATE TABLE IF NOT EXISTS gamedb.player_last_login_memory
(
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class LowCardinality(String),
    server_id UInt8,
    server_name LowCardinality(String),
    last_login_at DateTime64(3),
    last_logout_at Nullable(DateTime64(3)),
    last_ip IPv4,
    last_device_type LowCardinality(String),
    last_app_version LowCardinality(String),
    total_playtime_minutes UInt32,
    vip_level UInt8,
    guild_id Nullable(UInt64),
    guild_name Nullable(String),
    last_map_id UInt16,
    last_position_x Float32,
    last_position_y Float32,
    last_position_z Float32,
    currency_gold UInt64,
    currency_diamond UInt32,
    inventory_slots_used UInt16,
    created_at DateTime64(3),
    updated_at DateTime64(3)
)
ENGINE = Memory();

-- 데이터 복사
INSERT INTO gamedb.player_last_login_memory
SELECT * FROM gamedb.player_last_login;


-- ============================================================
-- 검증 쿼리
-- ============================================================

-- 테이블별 데이터 수 확인
SELECT 'original' AS table_name, count() AS total_players
FROM gamedb.player_last_login
UNION ALL
SELECT 'optimized' AS table_name, count() AS total_players
FROM gamedb.player_last_login_optimized
UNION ALL
SELECT 'memory' AS table_name, count() AS total_players
FROM gamedb.player_last_login_memory;

-- 파트 정보 비교 (원본 vs 최적화)
SELECT
    table,
    partition,
    name,
    rows,
    bytes_on_disk,
    primary_key_bytes_in_memory,
    marks
FROM system.parts
WHERE database = 'gamedb'
  AND table IN ('player_last_login', 'player_last_login_optimized')
  AND active
ORDER BY table, name;

-- 인덱스 정보 확인
SELECT
    table,
    name,
    type,
    expr,
    granularity
FROM system.data_skipping_indices
WHERE database = 'gamedb'
  AND table IN ('player_last_login', 'player_last_login_optimized')
ORDER BY table;
