-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 6. Settings Profile (쿼리 리소스 제한)
-- ============================================

-- Settings Profile 개념:
-- - 쿼리 실행 시 적용되는 설정 그룹
-- - 메모리, 실행 시간, 스레드 수 등 제한
-- - 사용자 또는 역할에 적용

-- ============================================
-- Settings Profile 생성
-- ============================================

-- 1) 분석가용 프로필 (중간 수준 제한)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_analyst_profile
SETTINGS
    max_memory_usage = 10000000000,       -- 10GB
    max_execution_time = 300,              -- 5분
    max_threads = 4,
    max_rows_to_read = 100000000,          -- 1억 행
    max_result_rows = 1000000,             -- 100만 행
    max_bytes_to_read = 10000000000,       -- 10GB
    readonly = 1;                          -- 읽기 전용 모드

-- 2) BI 사용자용 프로필 (더 제한적)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_bi_profile
SETTINGS
    max_memory_usage = 5000000000,         -- 5GB
    max_execution_time = 60,               -- 1분
    max_threads = 2,
    max_result_rows = 100000,              -- 10만 행
    max_bytes_to_read = 5000000000,        -- 5GB
    readonly = 1;

-- 3) 데이터 엔지니어용 프로필 (관대함)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_engineer_profile
SETTINGS
    max_memory_usage = 50000000000,        -- 50GB
    max_execution_time = 3600,             -- 1시간
    max_threads = 16,
    max_rows_to_read = 1000000000,         -- 10억 행
    max_result_rows = 10000000;            -- 1000만 행
    -- readonly는 설정하지 않음 (쓰기 가능)

-- 4) 파트너용 프로필 (매우 제한적)
CREATE SETTINGS PROFILE IF NOT EXISTS demo_partner_profile
SETTINGS
    max_memory_usage = 2000000000,         -- 2GB
    max_execution_time = 30,               -- 30초
    max_threads = 2,
    max_result_rows = 10000,               -- 1만 행
    max_bytes_to_read = 1000000000,        -- 1GB
    readonly = 1;


-- ============================================
-- Profile을 Role/User에 적용
-- ============================================

-- 역할에 프로필 적용
ALTER ROLE rbac_demo_analyst SETTINGS PROFILE demo_analyst_profile;
ALTER ROLE rbac_demo_readonly SETTINGS PROFILE demo_bi_profile;
ALTER ROLE rbac_demo_engineer SETTINGS PROFILE demo_engineer_profile;
ALTER ROLE rbac_demo_partner SETTINGS PROFILE demo_partner_profile;

-- 또는 사용자에게 직접 적용 (선택적)
-- ALTER USER demo_analyst SETTINGS PROFILE demo_analyst_profile;
-- ALTER USER demo_bi_user SETTINGS PROFILE demo_bi_profile;
-- ALTER USER demo_engineer SETTINGS PROFILE demo_engineer_profile;
-- ALTER USER demo_partner SETTINGS PROFILE demo_partner_profile;


-- ============================================
-- 검증: Settings Profile 확인
-- ============================================

SELECT '=== Created Settings Profiles ===' as info;
SELECT
    name,
    id,
    storage,
    num_elements,
    apply_to_all,
    arrayStringConcat(apply_to_list, ', ') as applied_to
FROM system.settings_profiles
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== Settings Profile Elements ===' as info;
SELECT
    profile_name,
    setting_name,
    value,
    readonly,
    inherit_profile
FROM system.settings_profile_elements
WHERE profile_name LIKE 'demo_%'
ORDER BY profile_name, setting_name;

-- 역할에 적용된 프로필 확인
SELECT '=== Profiles Applied to Roles ===' as info;
SELECT
    name as role_name,
    arrayStringConcat(settings.names, ', ') as settings_profiles
FROM system.roles
WHERE name LIKE 'rbac_demo%'
ORDER BY name;


-- ============================================
-- 테스트 가이드 (실제 사용자로 로그인 후 테스트)
-- ============================================

-- demo_analyst로 로그인 후 실행:
-- SELECT getSetting('max_memory_usage');  -- 10000000000 반환
-- SELECT getSetting('max_execution_time');  -- 300 반환
-- SELECT name, value FROM system.settings WHERE changed = 1;

-- 제한 초과 테스트 (의도적으로 큰 쿼리 - 시간 제한 테스트)
-- SELECT sleep(1) FROM numbers(400);
-- → max_execution_time 초과로 취소됨

-- 메모리 제한 테스트
-- SELECT groupArray(number) FROM numbers(100000000);
-- → max_memory_usage 초과로 에러

-- 결과 행 제한 테스트
-- SELECT * FROM numbers(2000000);
-- → max_result_rows 초과로 에러

-- readonly 설정 테스트
-- INSERT INTO rbac_demo.sales VALUES (999, 'TEST', 'Test', 0, today(), 0);
-- → readonly=1로 인해 에러


-- ============================================
-- 주요 Settings 설명
-- ============================================

-- max_memory_usage: 단일 쿼리가 사용할 수 있는 최대 메모리
-- max_execution_time: 쿼리 실행 최대 시간 (초)
-- max_threads: 쿼리 실행 시 사용할 최대 스레드 수
-- max_rows_to_read: 읽을 수 있는 최대 행 수
-- max_result_rows: 결과로 반환할 수 있는 최대 행 수
-- max_bytes_to_read: 읽을 수 있는 최대 바이트 수
-- readonly: 0=제한없음, 1=읽기만, 2=읽기+SET만
