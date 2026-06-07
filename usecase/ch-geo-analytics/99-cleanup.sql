-- ============================================================================
-- ch-geo-analytics Step 99: Cleanup
-- ch-geo-analytics 99단계: 정리
-- ============================================================================
-- Removes all objects created by this lab. Run this when you are done.
-- 이 랩에서 만든 모든 객체를 삭제합니다. 실습 종료 후 실행하세요.
-- ============================================================================

DROP VIEW  IF EXISTS geo_analytics.demand_by_hex_hour_mv;
DROP TABLE IF EXISTS geo_analytics.demand_by_hex_hour;
DROP TABLE IF EXISTS geo_analytics.trips;
DROP TABLE IF EXISTS geo_analytics.service_zones;
DROP TABLE IF EXISTS geo_analytics.hotspots;
DROP DATABASE IF EXISTS geo_analytics;

SELECT 'Cleanup complete.' AS done;
