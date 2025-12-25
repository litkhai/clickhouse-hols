-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Insert Test Data
-- ClickHouse Index Granularity Point Query 벤치마크 - 테스트 데이터 삽입
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Generate and insert 2 million test records
-- 목적: 200만 건의 테스트 데이터 생성 및 삽입
-- ============================================================================

-- ============================================================================
-- Insert test data into base table (G8192)
-- 기본 테이블(G8192)에 테스트 데이터 삽입
-- ============================================================================
-- Dataset: 2,000,000 player records
-- 데이터셋: 2,000,000개의 플레이어 레코드
-- ============================================================================

SELECT 'Inserting 2,000,000 records into player_g8192... / player_g8192에 2,000,000개 레코드 삽입 중...';

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
    toIPv4(concat(
        toString(rand() % 256), '.',
        toString(rand() % 256), '.',
        toString(rand() % 256), '.',
        toString(rand() % 256)
    )) AS last_ip,
    arrayElement(['PC','Android','iOS','Console'], rand() % 4 + 1) AS last_device_type,
    rand() % 50000 AS total_playtime_minutes,
    rand() % 10 AS vip_level,
    if(rand() % 3 = 0, NULL, rand() % 10000) AS guild_id,
    if(rand() % 3 = 0, NULL, concat('Guild_', toString(rand() % 1000))) AS guild_name,
    rand() % 100000000 AS currency_gold,
    rand() % 10000 AS currency_diamond,
    rand() % 200 AS inventory_slots_used
FROM numbers(2000000);

SELECT '✓ Completed inserting data into player_g8192 / player_g8192에 데이터 삽입 완료';

-- ============================================================================
-- Copy data to other granularity tables
-- 다른 granularity 테이블로 데이터 복사
-- ============================================================================

SELECT 'Copying data to player_g256... / player_g256로 데이터 복사 중...';
INSERT INTO granularity_test.player_g256 SELECT * FROM granularity_test.player_g8192;
SELECT '✓ Completed copying data to player_g256 / player_g256로 데이터 복사 완료';

SELECT 'Copying data to player_g1024... / player_g1024로 데이터 복사 중...';
INSERT INTO granularity_test.player_g1024 SELECT * FROM granularity_test.player_g8192;
SELECT '✓ Completed copying data to player_g1024 / player_g1024로 데이터 복사 완료';

SELECT 'Copying data to player_g4096... / player_g4096로 데이터 복사 중...';
INSERT INTO granularity_test.player_g4096 SELECT * FROM granularity_test.player_g8192;
SELECT '✓ Completed copying data to player_g4096 / player_g4096로 데이터 복사 완료';

-- ============================================================================
-- Verify row counts
-- 행 개수 확인
-- ============================================================================

SELECT
    'Verification: Row counts by table / 검증: 테이블별 행 개수' AS info;

SELECT
    name AS table_name,
    total_rows,
    formatReadableSize(total_bytes) AS compressed_size
FROM system.tables
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY name;

-- ============================================================================
-- Sample data preview
-- 샘플 데이터 미리보기
-- ============================================================================

SELECT 'Sample data (first 3 rows from player_g8192) / 샘플 데이터 (player_g8192에서 처음 3개 행)' AS info;

SELECT
    player_id,
    player_name,
    character_name,
    character_level,
    character_class,
    server_name,
    vip_level
FROM granularity_test.player_g8192
ORDER BY player_id
LIMIT 3;

SELECT '✓ All data insertion completed successfully / 모든 데이터 삽입이 성공적으로 완료되었습니다';
