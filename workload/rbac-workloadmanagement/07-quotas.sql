-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 7. Quota (사용량 제한)
-- ============================================

-- Quota 개념:
-- - 시간 기반 사용량 제한 (시간당, 일당 등)
-- - 쿼리 수, 결과 행 수, 읽기 바이트 등 제한
-- - 리소스 남용 방지 및 공정한 리소스 분배

-- ============================================
-- Quota 생성
-- ============================================

-- 1) 분석가용 Quota (시간당 제한)
CREATE QUOTA IF NOT EXISTS demo_analyst_quota
FOR INTERVAL 1 hour
MAX queries = 100,                         -- 시간당 최대 100개 쿼리
    query_selects = 80,                    -- 시간당 최대 80개 SELECT
    query_inserts = 0,                     -- INSERT 불가 (readonly)
    result_rows = 10000000,                -- 총 1000만 행 결과
    read_rows = 1000000000,                -- 총 10억 행 읽기
    read_bytes = 100000000000,             -- 총 100GB 읽기
    execution_time = 1800                  -- 총 30분 실행 시간
TO rbac_demo_analyst;

-- 2) BI 사용자용 Quota (더 제한적, 짧은 간격)
CREATE QUOTA IF NOT EXISTS demo_bi_quota
FOR INTERVAL 1 hour
MAX queries = 200,                         -- 많은 쿼리 허용 (대시보드용)
    query_selects = 200,
    result_rows = 1000000,                 -- 총 100만 행
    read_rows = 100000000,                 -- 총 1억 행
    read_bytes = 10000000000,              -- 총 10GB
    execution_time = 600                   -- 총 10분
TO rbac_demo_readonly;

-- 3) 데이터 엔지니어용 Quota (관대한 제한)
CREATE QUOTA IF NOT EXISTS demo_engineer_quota
FOR INTERVAL 1 day
MAX queries = 1000,
    query_selects = 800,
    query_inserts = 200,
    result_rows = 100000000,               -- 총 1억 행
    read_bytes = 1000000000000,            -- 총 1TB
    execution_time = 36000                 -- 총 10시간
TO rbac_demo_engineer;

-- 4) 파트너용 Quota (매우 제한적)
CREATE QUOTA IF NOT EXISTS demo_partner_quota
FOR INTERVAL 1 hour
MAX queries = 50,                          -- 시간당 50개
    query_selects = 50,
    result_rows = 100000,                  -- 총 10만 행
    read_rows = 10000000,                  -- 총 1000만 행
    read_bytes = 1000000000,               -- 총 1GB
    execution_time = 300,                  -- 총 5분
    errors = 10                            -- 최대 10개 에러
TO rbac_demo_partner;

-- 5) 다중 구간 Quota 예제 (시간+일 이중 제한)
CREATE QUOTA IF NOT EXISTS demo_multi_interval_quota
FOR INTERVAL 1 hour MAX queries = 100, execution_time = 600,
FOR INTERVAL 1 day MAX queries = 1000, execution_time = 7200
TO rbac_demo_analyst;

-- 참고: 마지막에 생성된 Quota가 적용됨
-- demo_analyst에게는 demo_multi_interval_quota가 적용됨


-- ============================================
-- 검증: Quota 확인
-- ============================================

SELECT '=== Created Quotas ===' as info;
SELECT
    name,
    id,
    storage,
    arrayStringConcat(all_keys, ', ') as keys,
    arrayStringConcat(apply_to_list, ', ') as applied_to
FROM system.quotas
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== Quota Limits ===' as info;
SELECT
    quota_name,
    duration,
    queries as max_queries,
    query_selects as max_selects,
    query_inserts as max_inserts,
    errors as max_errors,
    result_rows as max_result_rows,
    read_rows as max_read_rows,
    formatReadableSize(read_bytes) as max_read_bytes,
    execution_time as max_execution_seconds
FROM system.quota_limits
WHERE quota_name LIKE 'demo_%'
ORDER BY quota_name, duration;

-- Quota 사용량 확인 (실시간)
SELECT '=== Quota Usage ===' as info;
SELECT
    quota_name,
    quota_key,
    duration,
    queries,
    query_selects,
    errors,
    result_rows,
    read_rows,
    formatReadableSize(read_bytes) as read_bytes,
    execution_time
FROM system.quota_usage
WHERE quota_name LIKE 'demo_%';


-- ============================================
-- 테스트 가이드 (실제 사용자로 로그인 후 테스트)
-- ============================================

-- demo_analyst로 로그인 후:
-- 1) 현재 Quota 사용량 확인
-- SELECT * FROM system.quota_usage;

-- 2) 쿼리 여러 번 실행 후 사용량 변화 확인
-- SELECT count() FROM rbac_demo.sales;  -- 여러 번 실행
-- SELECT * FROM system.quota_usage;

-- 3) Quota 한계 테스트 (과도한 쿼리 실행)
-- 아래 쿼리를 100번 이상 실행하여 queries 제한 도달:
-- SELECT sleep(0.1);

-- 4) 에러 카운트 테스트
-- 의도적으로 잘못된 쿼리 실행:
-- SELECT * FROM non_existent_table;  -- 여러 번 실행
-- SELECT * FROM system.quota_usage;  -- errors 카운트 증가 확인


-- ============================================
-- Quota 관리 명령어
-- ============================================

-- Quota 수정
-- ALTER QUOTA demo_analyst_quota
-- FOR INTERVAL 1 hour MAX queries = 150;

-- Quota 삭제
-- DROP QUOTA IF EXISTS demo_analyst_quota;

-- Quota를 특정 역할에서 제거
-- ALTER QUOTA demo_analyst_quota TO NONE;

-- Quota 재할당
-- ALTER QUOTA demo_analyst_quota TO rbac_demo_analyst, rbac_demo_readonly;
