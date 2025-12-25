-- ============================================================
-- ClickHouse 스키마: Point Query 최적화
-- 핵심: Primary Key ORDER BY + Bloom Filter Index
-- ============================================================

CREATE DATABASE IF NOT EXISTS gamedb;

CREATE TABLE gamedb.player_last_login
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

    -- ============================================
    -- Bloom Filter Index: player_id 기반 Point Query 최적화
    -- ============================================
    INDEX idx_player_id_bloom player_id TYPE bloom_filter(0.01) GRANULARITY 1
)
ENGINE = MergeTree()
-- ============================================
-- Primary Key: player_id 기반 ORDER BY
-- Point Query 시 Binary Search로 빠른 조회
-- ============================================
ORDER BY player_id
SETTINGS
    -- index_granularity: 기본값 8192 유지
    -- 200만 rows / 8192 = ~244 granules
    index_granularity = 8192;


-- ============================================================
-- 200만 유저 데이터 생성
-- ============================================================

INSERT INTO gamedb.player_last_login
SELECT
    number + 1 AS player_id,
    concat('Player_', toString(number + 1)) AS player_name,
    (number + 1) * 10 + rand() % 5 AS character_id,
    concat('Hero_', toString(number + 1), '_', toString(rand() % 100)) AS character_name,
    (rand() % 100) + 1 AS character_level,
    arrayElement(['전사','마법사','궁수','도적','성직자','소환사'], rand() % 6 + 1) AS character_class,
    (rand() % 8) + 1 AS server_id,
    arrayElement(['아시아-1','아시아-2','유럽-1','유럽-2','북미-1','북미-2','남미-1','오세아니아-1'], rand() % 8 + 1) AS server_name,
    now() - toIntervalDay(rand() % 30) AS last_login_at,
    if(rand() % 2 = 0, now() - toIntervalDay(rand() % 30), NULL) AS last_logout_at,
    toIPv4(concat(toString(rand() % 256), '.', toString(rand() % 256), '.', toString(rand() % 256), '.', toString(rand() % 256))) AS last_ip,
    arrayElement(['iOS','Android','PC','Steam'], rand() % 4 + 1) AS last_device_type,
    arrayElement(['1.0.0','1.0.1','1.1.0','1.2.0','1.2.1'], rand() % 5 + 1) AS last_app_version,
    rand() % 50000 AS total_playtime_minutes,
    rand() % 11 AS vip_level,
    if(rand() % 10 > 3, rand() % 10000 + 1, NULL) AS guild_id,
    if(rand() % 10 > 3, concat('Guild_', toString(rand() % 1000)), NULL) AS guild_name,
    (rand() % 200) + 1 AS last_map_id,
    (rand() % 1000000) / 1000.0 AS last_position_x,
    (rand() % 1000000) / 1000.0 AS last_position_y,
    (rand() % 100000) / 1000.0 AS last_position_z,
    rand() % 100000000 AS currency_gold,
    rand() % 10000 AS currency_diamond,
    rand() % 200 AS inventory_slots_used,
    now64(3) AS created_at,
    now64(3) AS updated_at
FROM numbers(2000000);

-- 데이터 최적화 (파트 병합)
OPTIMIZE TABLE gamedb.player_last_login FINAL;

-- ============================================================
-- 검증 쿼리
-- ============================================================

-- 데이터 수 확인
SELECT count() AS total_players FROM gamedb.player_last_login;

-- 테이블 구조 확인
DESCRIBE TABLE gamedb.player_last_login;

-- 인덱스 확인
SELECT
    name,
    type,
    expr,
    granularity
FROM system.data_skipping_indices
WHERE table = 'player_last_login' AND database = 'gamedb';

-- 파트 정보 확인
SELECT
    partition,
    name,
    rows,
    bytes_on_disk,
    primary_key_bytes_in_memory,
    marks
FROM system.parts
WHERE database = 'gamedb' AND table = 'player_last_login' AND active;
