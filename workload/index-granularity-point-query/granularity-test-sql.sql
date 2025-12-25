-- ============================================================
-- ClickHouse Index Granularity 성능 테스트 SQL
-- ============================================================

-- ============================================================
-- 1. 테스트 데이터베이스 생성
-- ============================================================

CREATE DATABASE IF NOT EXISTS granularity_test;

-- ============================================================
-- 2. 테스트 테이블 생성 (Granularity별)
-- ============================================================

-- 2.1 Granularity = 256 (Point Query 최적화)
CREATE TABLE granularity_test.player_g256 (
    player_id UInt64,
    player_name String,
    character_id UInt64,
    character_name String,
    character_level UInt16,
    character_class LowCardinality(String),
    server_id UInt8,
    server_name LowCardinality(String),
    last_login_at DateTime64(3),
    last_ip IPv4,
    last_device_type LowCardinality(String),
    total_playtime_minutes UInt32,
    vip_level UInt8,
    guild_id Nullable(UInt64),
    guild_name Nullable(String),
    currency_gold UInt64,
    currency_diamond UInt32,
    inventory_slots_used UInt16
)
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 256;

-- 2.2 Granularity = 1024
CREATE TABLE granularity_test.player_g1024 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 1024;

-- 2.3 Granularity = 4096
CREATE TABLE granularity_test.player_g4096 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 4096;

-- 2.4 Granularity = 8192 (기본값)
CREATE TABLE granularity_test.player_g8192 AS granularity_test.player_g256
ENGINE = MergeTree()
ORDER BY player_id
SETTINGS index_granularity = 8192;

-- ============================================================
-- 3. 테스트 데이터 생성 (200만 rows)
-- ============================================================

-- 3.1 G8192 테이블에 데이터 삽입
INSERT INTO granularity_test.player_g8192
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
    toIPv4(concat(toString(rand() % 256), '.', toString(rand() % 256), '.', toString(rand() % 256), '.', toString(rand() % 256))) AS last_ip,
    arrayElement(['PC','Android','iOS','Console'], rand() % 4 + 1) AS last_device_type,
    rand() % 50000 AS total_playtime_minutes,
    rand() % 10 AS vip_level,
    if(rand() % 3 = 0, NULL, rand() % 10000) AS guild_id,
    if(rand() % 3 = 0, NULL, concat('Guild_', toString(rand() % 1000))) AS guild_name,
    rand() % 100000000 AS currency_gold,
    rand() % 10000 AS currency_diamond,
    rand() % 200 AS inventory_slots_used
FROM numbers(2000000);

-- 3.2 다른 테이블에 데이터 복사
INSERT INTO granularity_test.player_g256 SELECT * FROM granularity_test.player_g8192;
INSERT INTO granularity_test.player_g1024 SELECT * FROM granularity_test.player_g8192;
INSERT INTO granularity_test.player_g4096 SELECT * FROM granularity_test.player_g8192;

-- ============================================================
-- 4. 테이블 메타데이터 확인
-- ============================================================

-- 4.1 테이블별 저장 정보 확인
SELECT 
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS compressed_size,
    formatReadableSize(total_bytes_uncompressed) AS uncompressed_size,
    total_marks,
    round(total_bytes / total_bytes_uncompressed * 100, 2) AS compression_ratio_pct
FROM system.tables 
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY name;

-- 4.2 Granularity 설정 확인
SELECT 
    name,
    extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity
FROM system.tables 
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%';

-- ============================================================
-- 5. Point Query 성능 테스트
-- ============================================================

-- 5.1 단일 Point Query 테스트
SELECT * FROM granularity_test.player_g256 WHERE player_id = 500000;
SELECT * FROM granularity_test.player_g1024 WHERE player_id = 500000;
SELECT * FROM granularity_test.player_g4096 WHERE player_id = 500000;
SELECT * FROM granularity_test.player_g8192 WHERE player_id = 500000;

-- 5.2 IN Query 테스트 (다중 Point Query)
SELECT count() FROM granularity_test.player_g256 
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

SELECT count() FROM granularity_test.player_g8192 
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

-- ============================================================
-- 6. 쿼리 로그 기반 성능 분석
-- ============================================================

-- 6.1 로그 플러시 (즉시 반영)
SYSTEM FLUSH LOGS;

-- 6.2 최근 테스트 쿼리 성능 확인
SELECT 
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_size,
    result_rows,
    substring(query, 1, 80) AS query_preview
FROM system.query_log 
WHERE type = 'QueryFinish'
  AND query LIKE '%granularity_test.player_g%'
  AND query NOT LIKE '%system%'
ORDER BY event_time DESC
LIMIT 20;

-- 6.3 Granularity별 성능 비교 (집계)
SELECT 
    CASE 
        WHEN query LIKE '%player_g256%' THEN 'G256'
        WHEN query LIKE '%player_g1024%' THEN 'G1024'
        WHEN query LIKE '%player_g4096%' THEN 'G4096'
        WHEN query LIKE '%player_g8192%' THEN 'G8192'
    END AS granularity,
    count() AS query_count,
    round(avg(query_duration_ms), 2) AS avg_duration_ms,
    round(avg(read_rows), 0) AS avg_read_rows,
    formatReadableSize(avg(read_bytes)) AS avg_read_size
FROM system.query_log 
WHERE type = 'QueryFinish'
  AND query LIKE '%granularity_test.player_g%'
  AND query LIKE '%player_id%'
  AND query NOT LIKE '%system%'
  AND event_time > now() - INTERVAL 1 HOUR
GROUP BY granularity
ORDER BY granularity;

-- ============================================================
-- 7. EXPLAIN을 통한 실행 계획 확인
-- ============================================================

-- 7.1 G256 실행 계획 (indexes 포함)
EXPLAIN indexes = 1
SELECT * FROM granularity_test.player_g256 WHERE player_id = 500000;

-- 7.2 G8192 실행 계획 (indexes 포함)
EXPLAIN indexes = 1
SELECT * FROM granularity_test.player_g8192 WHERE player_id = 500000;

-- ============================================================
-- 8. Parts 및 Marks 상세 확인
-- ============================================================

-- 8.1 Parts 정보
SELECT 
    table,
    name AS part_name,
    rows,
    marks,
    formatReadableSize(bytes_on_disk) AS size_on_disk
FROM system.parts
WHERE database = 'granularity_test'
  AND table LIKE 'player_g%'
  AND active = 1
ORDER BY table;

-- ============================================================
-- 9. 정리 (선택적)
-- ============================================================

-- DROP DATABASE granularity_test;
