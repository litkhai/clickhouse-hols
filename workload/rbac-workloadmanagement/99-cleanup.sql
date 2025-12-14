-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 99. 정리 스크립트
-- ============================================

-- ⚠️  주의: 이 스크립트는 모든 테스트 데이터 및 설정을 삭제합니다.
-- ⚠️  실행 전 반드시 확인하세요!

-- 정리 순서:
-- 1. Row Policies (다른 객체에 의존성 있음)
-- 2. Quotas
-- 3. Settings Profiles
-- 4. Users (Role 부여 해제)
-- 5. Roles (Grants 자동 삭제됨)
-- 6. Workloads (자식부터 삭제)
-- 7. Resources
-- 8. Database (테이블 포함)

-- ============================================
-- 1. Row Policies 삭제
-- ============================================

DROP ROW POLICY IF EXISTS apac_only_policy ON rbac_demo.sales;
DROP ROW POLICY IF EXISTS all_regions_policy ON rbac_demo.sales;

SELECT '✓ Row Policies dropped' as status;


-- ============================================
-- 2. Quotas 삭제
-- ============================================

DROP QUOTA IF EXISTS demo_analyst_quota;
DROP QUOTA IF EXISTS demo_bi_quota;
DROP QUOTA IF EXISTS demo_engineer_quota;
DROP QUOTA IF EXISTS demo_partner_quota;
DROP QUOTA IF EXISTS demo_multi_interval_quota;

SELECT '✓ Quotas dropped' as status;


-- ============================================
-- 3. Settings Profiles 삭제
-- ============================================

DROP SETTINGS PROFILE IF EXISTS demo_analyst_profile;
DROP SETTINGS PROFILE IF EXISTS demo_bi_profile;
DROP SETTINGS PROFILE IF EXISTS demo_engineer_profile;
DROP SETTINGS PROFILE IF EXISTS demo_partner_profile;

SELECT '✓ Settings Profiles dropped' as status;


-- ============================================
-- 4. Users 삭제
-- ============================================

DROP USER IF EXISTS demo_bi_user;
DROP USER IF EXISTS demo_analyst;
DROP USER IF EXISTS demo_engineer;
DROP USER IF EXISTS demo_partner;

SELECT '✓ Users dropped' as status;


-- ============================================
-- 5. Roles 삭제 (Grants도 함께 삭제됨)
-- ============================================

DROP ROLE IF EXISTS rbac_demo_readonly;
DROP ROLE IF EXISTS rbac_demo_analyst;
DROP ROLE IF EXISTS rbac_demo_engineer;
DROP ROLE IF EXISTS rbac_demo_partner;

SELECT '✓ Roles dropped' as status;


-- ============================================
-- 6. Workloads 삭제 (자식부터)
-- ============================================

DROP WORKLOAD IF EXISTS demo_adhoc;
DROP WORKLOAD IF EXISTS demo_analytics;
DROP WORKLOAD IF EXISTS demo_realtime;
DROP WORKLOAD IF EXISTS demo_production;
DROP WORKLOAD IF EXISTS demo_admin;
DROP WORKLOAD IF EXISTS all;

SELECT '✓ Workloads dropped' as status;


-- ============================================
-- 7. Resources 삭제
-- ============================================

DROP RESOURCE IF EXISTS cpu;

SELECT '✓ Resources dropped' as status;


-- ============================================
-- 8. Database 및 테이블 삭제
-- ============================================

-- 테이블 개별 삭제 (선택적)
-- DROP TABLE IF EXISTS rbac_demo.sales;
-- DROP TABLE IF EXISTS rbac_demo.customers;

-- 데이터베이스 전체 삭제 (테이블 포함)
DROP DATABASE IF EXISTS rbac_demo;

SELECT '✓ Database dropped' as status;


-- ============================================
-- 정리 검증
-- ============================================

SELECT '=== Cleanup Verification ===' as info;

SELECT 'Remaining demo users:' as check, count() as count
FROM system.users
WHERE name LIKE 'demo_%';

SELECT 'Remaining demo roles:' as check, count() as count
FROM system.roles
WHERE name LIKE 'rbac_demo%';

SELECT 'Remaining demo profiles:' as check, count() as count
FROM system.settings_profiles
WHERE name LIKE 'demo_%';

SELECT 'Remaining demo quotas:' as check, count() as count
FROM system.quotas
WHERE name LIKE 'demo_%';

SELECT 'Remaining demo row policies:' as check, count() as count
FROM system.row_policies
WHERE database = 'rbac_demo';

SELECT 'Remaining demo workloads:' as check, count() as count
FROM system.workloads
WHERE name LIKE 'demo_%';

SELECT 'rbac_demo database exists:' as check, count() as count
FROM system.databases
WHERE name = 'rbac_demo';

-- 모든 count가 0이어야 함
SELECT '=== Cleanup Complete ===' as info;
