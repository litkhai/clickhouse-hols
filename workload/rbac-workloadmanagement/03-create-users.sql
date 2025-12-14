-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 3. 사용자 생성 및 역할 할당
-- ============================================

-- 사용자별 역할 매핑:
-- ┌──────────────────┬────────────────────────┬─────────────────┐
-- │ User             │ Role                   │ Purpose         │
-- ├──────────────────┼────────────────────────┼─────────────────┤
-- │ demo_bi_user     │ rbac_demo_readonly     │ BI 대시보드     │
-- │ demo_analyst     │ rbac_demo_analyst      │ 데이터 분석     │
-- │ demo_engineer    │ rbac_demo_engineer     │ 데이터 엔지니어 │
-- │ demo_partner     │ rbac_demo_partner      │ 외부 파트너     │
-- └──────────────────┴────────────────────────┴─────────────────┘

-- 1) BI 사용자 생성
CREATE USER IF NOT EXISTS demo_bi_user
    IDENTIFIED BY 'SecurePass123!'
    HOST ANY  -- 모든 호스트에서 접속 가능 (실제 환경에서는 IP 제한 권장)
    DEFAULT ROLE rbac_demo_readonly;

-- 역할 명시적 부여
GRANT rbac_demo_readonly TO demo_bi_user;

-- 2) 분석가 사용자 생성
CREATE USER IF NOT EXISTS demo_analyst
    IDENTIFIED WITH sha256_password BY 'AnalystPass456!'
    HOST ANY
    DEFAULT ROLE rbac_demo_analyst;

GRANT rbac_demo_analyst TO demo_analyst;

-- 3) 데이터 엔지니어 사용자 생성
CREATE USER IF NOT EXISTS demo_engineer
    IDENTIFIED BY 'EngineerPass789!'
    HOST ANY
    DEFAULT ROLE rbac_demo_engineer;

GRANT rbac_demo_engineer TO demo_engineer;

-- 4) 외부 파트너 사용자 생성
CREATE USER IF NOT EXISTS demo_partner
    IDENTIFIED BY 'PartnerPass000!'
    HOST ANY  -- 실제 환경에서는 'HOST IP '특정IP/CIDR'' 형태로 제한
    DEFAULT ROLE rbac_demo_partner;

GRANT rbac_demo_partner TO demo_partner;


-- ============================================
-- 검증: 생성된 사용자 확인
-- ============================================

SELECT '=== Created Users ===' as info;
SELECT
    name,
    auth_type,
    host_ip,
    host_names,
    default_roles_list,
    storage
FROM system.users
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== User Role Assignments ===' as info;
SELECT
    user_name,
    role_name,
    granted_role_name,
    granted_role_is_default,
    with_admin_option
FROM system.role_grants
WHERE user_name LIKE 'demo_%'
ORDER BY user_name, role_name;

-- 각 사용자가 실제로 가진 유효 권한 확인
SELECT '=== Effective Privileges for demo_bi_user ===' as info;
SELECT
    access_type,
    database,
    table,
    column
FROM system.grants
WHERE (user_name = 'demo_bi_user' OR role_name IN (
    SELECT role_name FROM system.role_grants WHERE user_name = 'demo_bi_user'
))
ORDER BY access_type, database, table;
