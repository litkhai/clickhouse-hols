-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 2. Role 생성 및 권한 부여
-- ============================================

-- 역할 계층 구조:
-- ┌──────────────────────────────────────────────┐
-- │ rbac_demo_engineer  (전체 권한)               │
-- ├──────────────────────────────────────────────┤
-- │ rbac_demo_analyst   (읽기 + 임시 테이블)      │
-- ├──────────────────────────────────────────────┤
-- │ rbac_demo_readonly  (읽기 전용)               │
-- ├──────────────────────────────────────────────┤
-- │ rbac_demo_partner   (제한된 읽기)             │
-- └──────────────────────────────────────────────┘

-- 1) 읽기 전용 역할 (BI Developers용)
CREATE ROLE IF NOT EXISTS rbac_demo_readonly;

-- rbac_demo 데이터베이스의 모든 테이블에 대한 읽기 권한
GRANT SELECT ON rbac_demo.* TO rbac_demo_readonly;

-- 2) 분석가 역할 (Data Analysts용)
CREATE ROLE IF NOT EXISTS rbac_demo_analyst;

-- 읽기 권한
GRANT SELECT ON rbac_demo.* TO rbac_demo_analyst;

-- 임시 테이블 생성 권한 (분석 작업용)
GRANT CREATE TEMPORARY TABLE ON *.* TO rbac_demo_analyst;

-- 3) 데이터 엔지니어 역할 (Data Engineers용)
CREATE ROLE IF NOT EXISTS rbac_demo_engineer;

-- rbac_demo 데이터베이스의 모든 권한
GRANT ALL ON rbac_demo.* TO rbac_demo_engineer;

-- 4) 외부 파트너 역할 (External Partners용)
CREATE ROLE IF NOT EXISTS rbac_demo_partner;

-- 특정 컬럼만 접근 가능 (customer_id는 제외)
GRANT SELECT(id, region, product, amount, sale_date)
    ON rbac_demo.sales
    TO rbac_demo_partner;

-- 고객 테이블은 접근 불가 (아무 권한도 부여하지 않음)


-- ============================================
-- 검증: 생성된 역할 확인
-- ============================================

SELECT '=== Created Roles ===' as info;
SELECT name, storage FROM system.roles
WHERE name LIKE 'rbac_demo%'
ORDER BY name;

SELECT '=== Granted Privileges ===' as info;
SELECT
    role_name,
    access_type,
    database,
    table,
    column,
    is_partial_revoke,
    grant_option
FROM system.grants
WHERE role_name LIKE 'rbac_demo%'
ORDER BY role_name, access_type, database, table;
