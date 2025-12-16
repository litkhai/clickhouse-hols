-- ============================================================================
-- MV vs RMV 테스트: Database 생성
-- MV vs RMV Test: Database Creation
-- ============================================================================

-- Database 생성
CREATE DATABASE IF NOT EXISTS mv_vs_rmv
COMMENT 'MV vs RMV Resource Efficiency Comparison Test';

-- 생성 확인
SHOW DATABASES LIKE 'mv_vs_rmv';

SELECT 'Database mv_vs_rmv created successfully' AS status;
