-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 4. Row Policy (행 수준 보안) 구현
-- ============================================

-- Row Policy 개념:
-- - 특정 조건을 만족하는 행만 접근 가능하도록 제한
-- - 멀티 테넌트 환경에서 데이터 격리
-- - 사용자/역할별로 다른 필터 조건 적용

-- 시나리오:
-- 1. partner는 APAC 지역 데이터만 볼 수 있음
-- 2. 다른 역할들은 모든 지역 데이터 접근 가능

-- ============================================
-- Row Policy 생성
-- ============================================

-- 1) APAC 지역만 접근 가능한 정책 (파트너용)
CREATE ROW POLICY IF NOT EXISTS apac_only_policy
ON rbac_demo.sales
FOR SELECT
USING region = 'APAC'
TO rbac_demo_partner;

-- 2) 모든 지역 접근 가능한 정책 (다른 역할용)
CREATE ROW POLICY IF NOT EXISTS all_regions_policy
ON rbac_demo.sales
FOR SELECT
USING 1=1  -- 항상 참 (모든 행 접근 가능)
TO rbac_demo_analyst, rbac_demo_engineer, rbac_demo_readonly;

-- 참고: Row Policy는 누적적으로 적용됩니다
-- - 여러 Policy가 적용된 경우 OR 조건으로 결합됨
-- - Policy가 하나도 없으면 기본적으로 모든 행 접근 가능


-- ============================================
-- 고급: 시간 기반 Row Policy 예제 (참고용)
-- ============================================

-- 최근 30일 데이터만 접근 가능한 정책 (비활성화됨)
-- CREATE ROW POLICY IF NOT EXISTS recent_data_only
-- ON rbac_demo.sales
-- FOR SELECT
-- USING sale_date >= today() - INTERVAL 30 DAY
-- TO rbac_demo_readonly;


-- ============================================
-- 검증: Row Policy 확인
-- ============================================

SELECT '=== Created Row Policies ===' as info;
SELECT
    database,
    table,
    name as policy_name,
    id,
    storage,
    select_filter,
    is_restrictive,
    apply_to_all,
    apply_to_list,
    apply_to_except
FROM system.row_policies
WHERE database = 'rbac_demo'
ORDER BY table, name;

-- Row Policy 상세 정보
SELECT '=== Row Policy Details ===' as info;
SELECT
    policy_name,
    database,
    table,
    arrayStringConcat(apply_to_list, ', ') as applies_to,
    select_filter as filter_condition
FROM system.row_policies
WHERE database = 'rbac_demo';


-- ============================================
-- 테스트 가이드 (실제 사용자로 로그인 후 테스트)
-- ============================================

-- demo_partner로 로그인 후 실행:
-- SELECT * FROM rbac_demo.sales;
-- → APAC 지역 데이터만 반환되어야 함 (3개 행)

-- demo_analyst로 로그인 후 실행:
-- SELECT * FROM rbac_demo.sales;
-- → 모든 지역 데이터 반환 (8개 행)

-- 지역별 카운트 확인 (demo_partner vs demo_analyst 비교):
-- SELECT region, count() as cnt FROM rbac_demo.sales GROUP BY region;
