-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Performance Test
-- ClickHouse Index Granularity Point Query 벤치마크 - 성능 테스트
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Execute point queries and compare performance across granularities
-- 목적: Point query 실행 및 granularity별 성능 비교
-- ============================================================================

-- ============================================================================
-- 1. Single Point Query Test
-- 1. 단일 Point Query 테스트
-- ============================================================================

SELECT '=== Single Point Query Test / 단일 Point Query 테스트 ===' AS info;
SELECT 'Testing player_id = 500000 across all tables / 모든 테이블에서 player_id = 500000 테스트' AS info;

-- Test G256
SELECT 'Testing G256...' AS info;
SELECT * FROM granularity_test.player_g256 WHERE player_id = 500000;

-- Test G1024
SELECT 'Testing G1024...' AS info;
SELECT * FROM granularity_test.player_g1024 WHERE player_id = 500000;

-- Test G4096
SELECT 'Testing G4096...' AS info;
SELECT * FROM granularity_test.player_g4096 WHERE player_id = 500000;

-- Test G8192
SELECT 'Testing G8192...' AS info;
SELECT * FROM granularity_test.player_g8192 WHERE player_id = 500000;

-- ============================================================================
-- 2. Multiple Point Query Test (IN clause)
-- 2. 다중 Point Query 테스트 (IN 절)
-- ============================================================================

SELECT '=== Multiple Point Query Test (IN clause) / 다중 Point Query 테스트 (IN 절) ===' AS info;
SELECT 'Testing with 5 player IDs / 5개의 player ID로 테스트' AS info;

-- Test G256
SELECT 'Testing G256 with IN clause...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g256
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

-- Test G1024
SELECT 'Testing G1024 with IN clause...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g1024
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

-- Test G4096
SELECT 'Testing G4096 with IN clause...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g4096
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

-- Test G8192
SELECT 'Testing G8192 with IN clause...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g8192
WHERE player_id IN (100000, 300000, 700000, 1000000, 1500000);

-- ============================================================================
-- 3. Range Query Test (Small Range)
-- 3. 범위 쿼리 테스트 (작은 범위)
-- ============================================================================

SELECT '=== Small Range Query Test / 작은 범위 쿼리 테스트 ===' AS info;
SELECT 'Testing player_id BETWEEN 500000 AND 500100 / player_id BETWEEN 500000 AND 500100 테스트' AS info;

-- Test G256
SELECT 'Testing G256 with small range...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g256
WHERE player_id BETWEEN 500000 AND 500100;

-- Test G1024
SELECT 'Testing G1024 with small range...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g1024
WHERE player_id BETWEEN 500000 AND 500100;

-- Test G4096
SELECT 'Testing G4096 with small range...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g4096
WHERE player_id BETWEEN 500000 AND 500100;

-- Test G8192
SELECT 'Testing G8192 with small range...' AS info;
SELECT count() AS result_count
FROM granularity_test.player_g8192
WHERE player_id BETWEEN 500000 AND 500100;

-- ============================================================================
-- 4. Execution Plan Analysis
-- 4. 실행 계획 분석
-- ============================================================================

SELECT '=== Execution Plan Analysis with EXPLAIN / EXPLAIN을 통한 실행 계획 분석 ===' AS info;

-- G256 Execution Plan
SELECT 'G256 Execution Plan:' AS info;
EXPLAIN indexes = 1
SELECT * FROM granularity_test.player_g256 WHERE player_id = 500000;

-- G8192 Execution Plan
SELECT 'G8192 Execution Plan:' AS info;
EXPLAIN indexes = 1
SELECT * FROM granularity_test.player_g8192 WHERE player_id = 500000;

-- ============================================================================
-- 5. Flush Logs for Analysis
-- 5. 분석을 위한 로그 플러시
-- ============================================================================

SELECT 'Flushing query logs... / 쿼리 로그 플러시 중...' AS info;
SYSTEM FLUSH LOGS;

SELECT '✓ Performance test completed / 성능 테스트 완료';
SELECT 'Run 05-analyze-results.sql to see performance comparison / 성능 비교를 보려면 05-analyze-results.sql을 실행하세요' AS next_step;
