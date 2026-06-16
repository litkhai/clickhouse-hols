-- ============================================================================
-- ads-analytics Step 99: Cleanup
-- ads-analytics 99단계: 정리
-- ============================================================================
-- Removes every object created by this lab. Run when you are done.
-- 이 랩에서 만든 모든 객체를 삭제합니다. 실습 종료 후 실행하세요.
-- ============================================================================

DROP VIEW       IF EXISTS ad_analytics.daily_campaign_cube_mv;
DROP TABLE      IF EXISTS ad_analytics.daily_campaign_cube;
DROP DICTIONARY IF EXISTS ad_analytics.campaign_dict;
DROP TABLE      IF EXISTS ad_analytics.campaign_meta;
DROP TABLE      IF EXISTS ad_analytics.cube_params;
DROP TABLE      IF EXISTS ad_analytics.ad_events;
DROP DATABASE   IF EXISTS ad_analytics;

SELECT 'Cleanup complete.' AS done;
