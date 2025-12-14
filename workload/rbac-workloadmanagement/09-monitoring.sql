-- ============================================
-- ClickHouse RBAC & Workload Management Lab
-- 9. 모니터링 및 검증 쿼리
-- ============================================

-- ============================================
-- 1. RBAC 모니터링
-- ============================================

SELECT '=== All Users ===' as info;
SELECT
    name,
    auth_type,
    arrayStringConcat(host_ip, ', ') as allowed_ips,
    arrayStringConcat(host_names, ', ') as allowed_hosts,
    arrayStringConcat(default_roles_list, ', ') as default_roles,
    storage
FROM system.users
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== All Roles ===' as info;
SELECT
    name,
    id,
    storage
FROM system.roles
WHERE name LIKE 'rbac_demo%'
ORDER BY name;

SELECT '=== User-Role Assignments ===' as info;
SELECT
    user_name,
    role_name,
    granted_role_is_default,
    with_admin_option
FROM system.role_grants
WHERE user_name LIKE 'demo_%' OR role_name LIKE 'rbac_demo%'
ORDER BY user_name, role_name;

SELECT '=== All Grants ===' as info;
SELECT
    user_name,
    role_name,
    access_type,
    database,
    table,
    column,
    is_partial_revoke,
    grant_option
FROM system.grants
WHERE (user_name LIKE 'demo_%' OR role_name LIKE 'rbac_demo%')
  AND database = 'rbac_demo'
ORDER BY role_name, access_type, table, column;

SELECT '=== Row Policies ===' as info;
SELECT
    database,
    table,
    name as policy_name,
    select_filter,
    is_restrictive,
    arrayStringConcat(apply_to_list, ', ') as applies_to
FROM system.row_policies
WHERE database = 'rbac_demo'
ORDER BY table, name;


-- ============================================
-- 2. Settings Profile 모니터링
-- ============================================

SELECT '=== Settings Profiles ===' as info;
SELECT
    name,
    id,
    num_elements,
    arrayStringConcat(apply_to_list, ', ') as applied_to,
    arrayStringConcat(apply_to_roles, ', ') as applied_to_roles
FROM system.settings_profiles
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== Profile Settings ===' as info;
SELECT
    profile_name,
    setting_name,
    value,
    min,
    max,
    readonly,
    inherit_profile
FROM system.settings_profile_elements
WHERE profile_name LIKE 'demo_%'
ORDER BY profile_name, setting_name;


-- ============================================
-- 3. Quota 모니터링
-- ============================================

SELECT '=== Quotas ===' as info;
SELECT
    name,
    id,
    arrayStringConcat(all_keys, ', ') as keys,
    arrayStringConcat(apply_to_list, ', ') as applied_to,
    arrayStringConcat(apply_to_roles, ', ') as applied_to_roles
FROM system.quotas
WHERE name LIKE 'demo_%'
ORDER BY name;

SELECT '=== Quota Limits ===' as info;
SELECT
    quota_name,
    duration,
    randomize_interval,
    queries as max_queries,
    query_selects as max_selects,
    query_inserts as max_inserts,
    errors as max_errors,
    result_rows as max_result_rows,
    read_rows as max_read_rows,
    formatReadableSize(read_bytes) as max_read_bytes,
    execution_time as max_execution_time
FROM system.quota_limits
WHERE quota_name LIKE 'demo_%'
ORDER BY quota_name, duration;

SELECT '=== Current Quota Usage ===' as info;
SELECT
    quota_name,
    quota_key,
    start_time,
    end_time,
    duration,
    queries,
    max_queries,
    query_selects,
    max_query_selects,
    errors,
    max_errors,
    result_rows,
    max_result_rows,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(max_read_bytes) as max_read_bytes,
    execution_time,
    max_execution_time
FROM system.quota_usage
WHERE quota_name LIKE 'demo_%';


-- ============================================
-- 4. Workload Scheduling 모니터링
-- ============================================

SELECT '=== Resources ===' as info;
SELECT
    name,
    read_disks,
    write_disks,
    create_query
FROM system.resources
ORDER BY name;

SELECT '=== Workloads ===' as info;
SELECT
    name,
    parent,
    create_query
FROM system.workloads
ORDER BY parent, name;

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
    formatReadableSize(dequeued_cost) as dequeued_cost,
    formatReadableSize(canceled_cost) as canceled_cost,
    busy_periods
FROM system.scheduler
ORDER BY resource, path;


-- ============================================
-- 5. 실시간 쿼리 모니터링
-- ============================================

SELECT '=== Current Running Queries ===' as info;
SELECT
    query_id,
    user,
    elapsed,
    formatReadableSize(read_rows) as read_rows,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory_usage,
    Settings['workload'] as workload,
    substring(query, 1, 100) as query_preview
FROM system.processes
WHERE user LIKE 'demo_%'
ORDER BY elapsed DESC;


-- ============================================
-- 6. 쿼리 로그 분석 (최근 1시간)
-- ============================================

SELECT '=== Queries by User (Last 1 Hour) ===' as info;
SELECT
    user,
    count() as query_count,
    countIf(type = 'QueryFinish') as successful_queries,
    countIf(type = 'ExceptionWhileProcessing') as failed_queries,
    sum(read_rows) as total_read_rows,
    formatReadableSize(sum(read_bytes)) as total_read_bytes,
    formatReadableSize(sum(memory_usage)) as total_memory,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(max(query_duration_ms), 2) as max_duration_ms
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND user LIKE 'demo_%'
GROUP BY user
ORDER BY query_count DESC;

SELECT '=== Top Slow Queries (Last 1 Hour) ===' as info;
SELECT
    user,
    type,
    query_duration_ms,
    formatReadableSize(read_rows) as read_rows,
    formatReadableSize(memory_usage) as memory_usage,
    exception,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND user LIKE 'demo_%'
  AND type != 'QueryStart'
ORDER BY query_duration_ms DESC
LIMIT 10;

SELECT '=== Failed Queries (Last 1 Hour) ===' as info;
SELECT
    event_time,
    user,
    query_duration_ms,
    exception,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE event_time > now() - INTERVAL 1 HOUR
  AND user LIKE 'demo_%'
  AND type = 'ExceptionWhileProcessing'
ORDER BY event_time DESC
LIMIT 20;


-- ============================================
-- 7. 권한 검증 쿼리
-- ============================================

-- 특정 사용자의 유효 권한 확인
SELECT '=== Effective Permissions for demo_analyst ===' as info;
WITH role_list AS (
    SELECT arrayJoin(default_roles_list) as role_name
    FROM system.users
    WHERE name = 'demo_analyst'
)
SELECT DISTINCT
    g.access_type,
    g.database,
    g.table,
    g.column,
    g.is_partial_revoke
FROM system.grants g
WHERE g.role_name IN (SELECT role_name FROM role_list)
   OR g.user_name = 'demo_analyst'
ORDER BY g.database, g.table, g.access_type, g.column;

-- 특정 테이블에 접근 가능한 사용자/역할 확인
SELECT '=== Who Can Access rbac_demo.sales? ===' as info;
SELECT DISTINCT
    coalesce(user_name, role_name) as principal,
    access_type,
    arrayStringConcat(groupArray(DISTINCT column), ', ') as columns
FROM system.grants
WHERE database = 'rbac_demo'
  AND table = 'sales'
GROUP BY principal, access_type
ORDER BY principal, access_type;


-- ============================================
-- 8. 성능 및 리소스 사용량
-- ============================================

SELECT '=== Memory Usage by User ===' as info;
SELECT
    user,
    count() as active_queries,
    formatReadableSize(sum(memory_usage)) as total_memory,
    formatReadableSize(avg(memory_usage)) as avg_memory,
    formatReadableSize(max(memory_usage)) as max_memory
FROM system.processes
WHERE user LIKE 'demo_%'
GROUP BY user;

SELECT '=== Table Statistics ===' as info;
SELECT
    database,
    name as table,
    engine,
    formatReadableSize(total_bytes) as size,
    total_rows as rows,
    formatReadableSize(total_bytes / nullIf(total_rows, 0)) as avg_row_size
FROM system.tables
WHERE database = 'rbac_demo'
ORDER BY total_bytes DESC;
