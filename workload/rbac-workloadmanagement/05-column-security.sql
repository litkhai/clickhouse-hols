-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 5. Column-Level Security (컬럼 수준 보안)
-- ============================================

-- 시나리오:
-- - customers 테이블에는 민감 정보(email, phone)가 있음
-- - 분석가는 고객 테이블을 볼 수 있지만 민감 정보는 제외
-- - 엔지니어만 모든 컬럼 접근 가능

-- ============================================
-- 기존 권한 확인
-- ============================================

SELECT '=== Current Grants on customers Table ===' as info;
SELECT
    role_name,
    access_type,
    database,
    table,
    column,
    is_partial_revoke
FROM system.grants
WHERE database = 'rbac_demo' AND table = 'customers'
ORDER BY role_name, access_type;


-- ============================================
-- 컬럼 수준 권한 설정
-- ============================================

-- 1) 분석가: 고객 테이블의 민감 컬럼 제외
-- 먼저 기존 SELECT 권한 제거
REVOKE SELECT ON rbac_demo.customers FROM rbac_demo_analyst;

-- 특정 컬럼만 부여 (email, phone 제외)
GRANT SELECT(id, name, region, created_at)
    ON rbac_demo.customers
    TO rbac_demo_analyst;

-- 2) 읽기 전용 역할: 분석가와 동일한 권한
REVOKE SELECT ON rbac_demo.customers FROM rbac_demo_readonly;

GRANT SELECT(id, name, region, created_at)
    ON rbac_demo.customers
    TO rbac_demo_readonly;

-- 3) 엔지니어: 모든 컬럼 접근 가능 (이미 부여됨)
-- rbac_demo_engineer는 ALL 권한을 가지므로 추가 작업 불필요

-- 4) 파트너: 고객 테이블 접근 불가 (권한 부여 안 함)
-- 이미 sales 테이블의 일부 컬럼만 접근 가능


-- ============================================
-- 검증: 컬럼 수준 권한 확인
-- ============================================

SELECT '=== Column-Level Grants ===' as info;
SELECT
    role_name,
    access_type,
    database,
    table,
    column,
    is_partial_revoke,
    grant_option
FROM system.grants
WHERE database = 'rbac_demo' AND table = 'customers'
ORDER BY role_name, column;

SELECT '=== All Grants Summary ===' as info;
SELECT
    role_name,
    access_type,
    table,
    arrayStringConcat(groupArray(column), ', ') as accessible_columns
FROM system.grants
WHERE database = 'rbac_demo' AND column IS NOT NULL
GROUP BY role_name, access_type, table
ORDER BY role_name, table;


-- ============================================
-- 테스트 가이드 (실제 사용자로 로그인 후 테스트)
-- ============================================

-- demo_analyst로 로그인 후 실행:
-- SELECT * FROM rbac_demo.customers;
-- → 에러 발생 (email, phone 컬럼 권한 없음)

-- SELECT id, name, region FROM rbac_demo.customers;
-- → 성공 (허용된 컬럼만 조회)

-- SELECT email FROM rbac_demo.customers;
-- → 에러: Access denied (권한 없음)

-- demo_engineer로 로그인 후 실행:
-- SELECT * FROM rbac_demo.customers;
-- → 성공 (모든 컬럼 조회 가능)

-- demo_partner로 로그인 후 실행:
-- SELECT * FROM rbac_demo.customers;
-- → 에러: Access denied (테이블 자체 권한 없음)
