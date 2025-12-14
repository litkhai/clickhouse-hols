-- ============================================
-- ReplacingMergeTree Lab - Cleanup
-- 8. 테스트 환경 정리
-- ============================================

-- 테이블 삭제 (선택사항)
DROP TABLE IF EXISTS blog_test.user_events_replacing;
DROP TABLE IF EXISTS blog_test.user_events_large;

-- 데이터베이스 삭제 (선택사항)
DROP DATABASE IF EXISTS blog_test;

-- 삭제 확인
SELECT
    database,
    name,
    engine
FROM system.tables
WHERE database = 'blog_test';
