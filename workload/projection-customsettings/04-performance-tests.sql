-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 4. 성능 테스트 및 분석
-- ============================================

-- ----------------------------------------------------------------------------
-- EXPLAIN 분석 (실행 계획)
-- ----------------------------------------------------------------------------

-- G=256 실행 계획
EXPLAIN indexes = 1
SELECT *
FROM granularity_test.player_g256
WHERE player_id = 500000
SETTINGS optimize_move_to_prewhere = 0;

-- G=8192 실행 계획
EXPLAIN indexes = 1
SELECT *
FROM granularity_test.player_g8192
WHERE player_id = 500000
SETTINGS optimize_move_to_prewhere = 0;


-- ----------------------------------------------------------------------------
-- Range Query 성능 테스트
-- ----------------------------------------------------------------------------

-- G=256: 범위 쿼리
SELECT
    'G=256' as test,
    count() as cnt,
    avg(character_level) as avg_level
FROM granularity_test.player_g256
WHERE player_id BETWEEN 100000 AND 200000;

-- G=8192: 범위 쿼리
SELECT
    'G=8192' as test,
    count() as cnt,
    avg(character_level) as avg_level
FROM granularity_test.player_g8192
WHERE player_id BETWEEN 100000 AND 200000;


-- ----------------------------------------------------------------------------
-- 집계 쿼리 성능 비교
-- ----------------------------------------------------------------------------

-- G=256: 집계
SELECT
    'G=256' as test,
    character_class,
    count() as player_count,
    avg(character_level) as avg_level,
    sum(total_playtime_minutes) as total_playtime
FROM granularity_test.player_g256
WHERE player_id > 1000000
GROUP BY character_class
ORDER BY player_count DESC;

-- G=8192: 집계
SELECT
    'G=8192' as test,
    character_class,
    count() as player_count,
    avg(character_level) as avg_level,
    sum(total_playtime_minutes) as total_playtime
FROM granularity_test.player_g8192
WHERE player_id > 1000000
GROUP BY character_class
ORDER BY player_count DESC;
