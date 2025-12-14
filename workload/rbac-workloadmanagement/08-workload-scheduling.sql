-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 8. Workload Scheduling (워크로드 스케줄링)
-- ============================================

-- Workload Scheduling 개념 (ClickHouse 25.4+):
-- - CPU/IO 리소스를 워크로드 간에 분배
-- - 우선순위 기반 스케줄링 (weight)
-- - 계층적 워크로드 구조 지원

-- 워크로드 계층 구조:
-- ┌─────────────────────────────────────────────────┐
-- │ all (root)                                      │
-- │ ├── demo_admin (관리자)                         │
-- │ └── demo_production                             │
-- │     ├── demo_realtime (weight=5, 우선순위 높음)│
-- │     ├── demo_analytics (weight=9)               │
-- │     └── demo_adhoc (weight=1, 우선순위 낮음)   │
-- └─────────────────────────────────────────────────┘

-- ============================================
-- CPU 리소스 정의
-- ============================================

-- CPU 리소스 생성 (마스터 스레드 + 워커 스레드)
CREATE RESOURCE IF NOT EXISTS cpu (MASTER THREAD, WORKER THREAD);


-- ============================================
-- Workload 계층 생성
-- ============================================

-- 1) 루트 워크로드
CREATE WORKLOAD IF NOT EXISTS all;

-- 2) 관리자 워크로드 (낮은 동시성)
CREATE WORKLOAD IF NOT EXISTS demo_admin IN all
SETTINGS max_concurrent_threads = 10;

-- 3) 프로덕션 워크로드 (메인 워크로드)
CREATE WORKLOAD IF NOT EXISTS demo_production IN all
SETTINGS max_concurrent_threads = 80;

-- 4) 실시간 워크로드 (대시보드, API) - 높은 우선순위
CREATE WORKLOAD IF NOT EXISTS demo_realtime IN demo_production
SETTINGS max_concurrent_threads = 30,
         weight = 5;

-- 5) 분석 워크로드 (분석가 쿼리) - 가장 높은 우선순위
CREATE WORKLOAD IF NOT EXISTS demo_analytics IN demo_production
SETTINGS max_concurrent_threads = 40,
         weight = 9;

-- 6) Ad-hoc 워크로드 (무거운 임시 쿼리) - 낮은 우선순위
CREATE WORKLOAD IF NOT EXISTS demo_adhoc IN demo_production
SETTINGS max_concurrent_threads = 20,
         weight = 1;


-- ============================================
-- 검증: Workload 및 Resource 확인
-- ============================================

SELECT '=== Created Resources ===' as info;
SELECT
    name as resource_name,
    read_disks,
    write_disks,
    create_query
FROM system.resources
ORDER BY name;

SELECT '=== Created Workloads ===' as info;
SELECT
    name as workload_name,
    parent,
    create_query
FROM system.workloads
ORDER BY name;

-- Workload 계층 구조 시각화
SELECT '=== Workload Hierarchy ===' as info;
SELECT
    name,
    parent,
    if(parent = '', 0, 1) as level
FROM system.workloads
ORDER BY level, parent, name;


-- ============================================
-- 워크로드 사용 방법
-- ============================================

-- 쿼리 실행 시 워크로드 지정:

-- 1) 실시간 쿼리 (높은 우선순위)
-- SELECT count() FROM rbac_demo.sales
-- SETTINGS workload = 'demo_realtime';

-- 2) 분석 쿼리 (가장 높은 우선순위)
-- SELECT region, sum(amount) FROM rbac_demo.sales
-- GROUP BY region
-- SETTINGS workload = 'demo_analytics';

-- 3) 무거운 ad-hoc 쿼리 (낮은 우선순위)
-- SELECT * FROM system.query_log
-- WHERE event_time > now() - INTERVAL 7 DAY
-- SETTINGS workload = 'demo_adhoc';

-- 4) 관리자 작업
-- OPTIMIZE TABLE rbac_demo.sales FINAL
-- SETTINGS workload = 'demo_admin';


-- ============================================
-- 사용자/역할별 기본 워크로드 설정 (선택적)
-- ============================================

-- 분석가: 기본적으로 analytics 워크로드 사용
-- ALTER ROLE rbac_demo_analyst SETTINGS workload = 'demo_analytics';

-- BI 사용자: realtime 워크로드 사용
-- ALTER ROLE rbac_demo_readonly SETTINGS workload = 'demo_realtime';

-- 엔지니어: 명시적 지정 없이 사용
-- ALTER ROLE rbac_demo_engineer SETTINGS workload = '';


-- ============================================
-- Workload 스케줄링 모니터링
-- ============================================

-- 스케줄러 상태 확인
SELECT '=== Scheduler Status ===' as info;
SELECT
    resource,
    path,
    type,
    weight,
    is_active,
    active_children,
    dequeued_requests,
    canceled_requests,
    dequeued_cost,
    canceled_cost,
    busy_periods,
    vruntime
FROM system.scheduler
ORDER BY resource, path;


-- ============================================
-- 고급: 동적 워크로드 제어
-- ============================================

-- 특정 워크로드의 리소스 제한 변경
-- ALTER WORKLOAD demo_adhoc
-- SETTINGS max_concurrent_threads = 10;  -- 더 제한적으로 변경

-- 워크로드의 우선순위 변경
-- ALTER WORKLOAD demo_realtime
-- SETTINGS weight = 10;  -- 더 높은 우선순위


-- ============================================
-- 워크로드 관리 명령어
-- ============================================

-- 워크로드 삭제 (자식 워크로드부터 삭제해야 함)
-- DROP WORKLOAD IF EXISTS demo_adhoc;
-- DROP WORKLOAD IF EXISTS demo_analytics;
-- DROP WORKLOAD IF EXISTS demo_realtime;
-- DROP WORKLOAD IF EXISTS demo_production;
-- DROP WORKLOAD IF EXISTS demo_admin;

-- 리소스 삭제 (모든 워크로드 삭제 후 가능)
-- DROP RESOURCE IF EXISTS cpu;


-- ============================================
-- 테스트 가이드
-- ============================================

-- 1) 서로 다른 워크로드로 동시 쿼리 실행
-- 터미널 1 (높은 우선순위):
-- SELECT sleep(1) FROM numbers(100) SETTINGS workload = 'demo_analytics';

-- 터미널 2 (낮은 우선순위):
-- SELECT sleep(1) FROM numbers(100) SETTINGS workload = 'demo_adhoc';

-- 터미널 3에서 스케줄러 상태 모니터링:
-- SELECT * FROM system.scheduler ORDER BY path;

-- 2) 실행 중인 쿼리의 워크로드 확인
-- SELECT
--     query_id,
--     user,
--     elapsed,
--     read_rows,
--     Settings['workload'] as workload,
--     query
-- FROM system.processes
-- WHERE query NOT LIKE '%system.processes%'
-- ORDER BY elapsed DESC;
