-- ============================================
-- ClickHouse Projection Lab - Cleanup
-- 99. 정리 스크립트
-- ============================================

-- 주의: 이 스크립트는 모든 테스트 데이터를 삭제합니다.
-- 실행 전 반드시 확인하세요!

-- Materialized View 삭제
DROP TABLE IF EXISTS projection_test.category_analysis_mv_source;
DROP TABLE IF EXISTS projection_test.category_analysis_mv;

-- 원본 테이블 삭제 (Projection도 함께 삭제됨)
DROP TABLE IF EXISTS projection_test.sales_events;

-- 데이터베이스 삭제
DROP DATABASE IF EXISTS projection_test;

-- 확인
SHOW DATABASES;
