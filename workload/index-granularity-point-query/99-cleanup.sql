-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Cleanup
-- ClickHouse Index Granularity Point Query 벤치마크 - 정리
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Clean up test database and tables
-- 목적: 테스트 데이터베이스 및 테이블 정리
-- ============================================================================

SELECT 'Cleaning up test database and tables... / 테스트 데이터베이스와 테이블을 정리하는 중...' AS info;

-- Drop all test tables
-- 모든 테스트 테이블 삭제
DROP TABLE IF EXISTS granularity_test.player_g256;
DROP TABLE IF EXISTS granularity_test.player_g1024;
DROP TABLE IF EXISTS granularity_test.player_g4096;
DROP TABLE IF EXISTS granularity_test.player_g8192;

SELECT '✓ All tables dropped / 모든 테이블이 삭제되었습니다' AS info;

-- Drop test database
-- 테스트 데이터베이스 삭제
DROP DATABASE IF EXISTS granularity_test;

SELECT '✓ Database dropped / 데이터베이스가 삭제되었습니다' AS info;

-- Verify cleanup
-- 정리 확인
SELECT
    count() AS remaining_tables,
    'tables remaining in granularity_test database / granularity_test 데이터베이스에 남은 테이블' AS info
FROM system.tables
WHERE database = 'granularity_test';

SELECT '✓ Cleanup completed successfully / 정리가 성공적으로 완료되었습니다' AS info;
