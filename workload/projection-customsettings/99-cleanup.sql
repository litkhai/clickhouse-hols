-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 99. 정리 (Cleanup)
-- ============================================

-- Projection 삭제
ALTER TABLE projection_granularity_test.events
DROP PROJECTION IF EXISTS user_lookup;

-- 테이블 삭제
DROP TABLE IF EXISTS projection_granularity_test.events;

-- 데이터베이스 삭제
DROP DATABASE IF EXISTS projection_granularity_test;


-- 확인
SELECT name
FROM system.databases
WHERE name = 'projection_granularity_test';
