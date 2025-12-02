-- ============================================================================
-- ClickHouse DELETE Mechanism Benchmark - Execute DELETE Operations
-- ClickHouse DELETE 메커니즘 벤치마크 - DELETE 작업 실행
-- ============================================================================
-- Created: 2025-12-01
-- 작성일: 2025-12-01
-- Purpose: Execute 10% data deletion using each method (user_id % 10 = 0)
-- 목적: 각 방식으로 10% 데이터 삭제 (user_id % 10 = 0)
-- ============================================================================

-- ============================================================================
-- Pre-deletion status check
-- 삭제 전 상태 확인
-- ============================================================================

SELECT 'Before DELETE operations' as checkpoint;
SELECT '삭제 작업 전' as checkpoint_kr;

SELECT 
    'alter_delete_table' as table_name,
    count() as total_rows,
    countIf(user_id % 10 = 0) as rows_to_delete,
    round(countIf(user_id % 10 = 0) * 100.0 / count(), 1) as delete_percentage
FROM delete_test.alter_delete_table

UNION ALL

SELECT 
    'replacing_merge_table',
    count(),
    countIf(user_id % 10 = 0 AND is_deleted = 0),
    round(countIf(user_id % 10 = 0 AND is_deleted = 0) * 100.0 / count(), 1)
FROM delete_test.replacing_merge_table

UNION ALL

SELECT 
    'collapsing_merge_table',
    count(),
    countIf(user_id % 10 = 0 AND sign = 1),
    round(countIf(user_id % 10 = 0 AND sign = 1) * 100.0 / count(), 1)
FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- 1. ALTER TABLE DELETE Execution
-- 1. ALTER TABLE DELETE 실행
-- ============================================================================
-- Feature: Uses mutation, asynchronous processing, physical deletion
-- 특징: Mutation 사용, 비동기 처리, 물리적 삭제
-- Timing: Only measures mutation start time (background processing)
-- 시간 측정: mutation 시작 시간만 측정 (백그라운드 처리)
-- ============================================================================

SELECT '=== 1. ALTER TABLE DELETE ===' as section;
SELECT 'Executing ALTER DELETE...' as status;
SELECT 'ALTER DELETE 실행 중...' as status_kr;
SELECT now() as start_time;

-- Execute actual deletion (asynchronous)
-- 실제 삭제 실행 (비동기)
ALTER TABLE delete_test.alter_delete_table 
DELETE WHERE user_id % 10 = 0
SETTINGS mutations_sync = 0;  -- Asynchronous execution / 비동기 실행

SELECT 'ALTER DELETE initiated' as status;
SELECT 'ALTER DELETE 시작됨' as status_kr;
SELECT now() as end_time;

-- Check mutation status
-- Mutation 상태 확인
SELECT 'Mutation Status / Mutation 상태:' as info;
SELECT 
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_fail_reason
FROM system.mutations
WHERE database = 'delete_test' 
  AND table = 'alter_delete_table'
ORDER BY create_time DESC
LIMIT 1;

-- ============================================================================
-- 2. ReplacingMergeTree Soft Delete Execution
-- 2. ReplacingMergeTree Soft Delete 실행
-- ============================================================================
-- Feature: INSERT with is_deleted=1 marking, synchronous execution, immediate reflection
-- 특징: INSERT로 is_deleted=1 마킹, 동기 실행, 즉시 반영
-- ============================================================================

SELECT '=== 2. ReplacingMergeTree Soft Delete ===' as section;
SELECT 'Executing ReplacingMergeTree soft delete...' as status;
SELECT 'ReplacingMergeTree soft delete 실행 중...' as status_kr;
SELECT now() as start_time;

-- Insert new version for records to delete (is_deleted=1)
-- 삭제할 데이터에 대해 새 버전 INSERT (is_deleted=1)
INSERT INTO delete_test.replacing_merge_table
SELECT 
    user_id,
    event_time,
    event_type,
    value,
    status,
    toUInt64(now64()) as version,  -- New version (current time in nanoseconds) / 새로운 버전 (현재 시간의 나노초)
    1 as is_deleted                 -- Delete marking / 삭제 마킹
FROM delete_test.replacing_merge_table
WHERE user_id % 10 = 0 AND is_deleted = 0;

SELECT 'ReplacingMergeTree soft delete completed' as status;
SELECT 'ReplacingMergeTree soft delete 완료' as status_kr;
SELECT now() as end_time;

-- Verify inserted delete markers
-- 삽입된 삭제 마커 확인
SELECT 
    'Delete markers inserted' as info,
    countIf(is_deleted = 1) as delete_marker_count
FROM delete_test.replacing_merge_table;

-- ============================================================================
-- 3. CollapsingMergeTree Collapsing Execution
-- 3. CollapsingMergeTree Collapsing 실행
-- ============================================================================
-- Feature: INSERT with sign=-1, synchronous execution, immediate reflection
-- 특징: INSERT로 sign=-1 추가, 동기 실행, 즉시 반영
-- ============================================================================

SELECT '=== 3. CollapsingMergeTree Collapsing ===' as section;
SELECT 'Executing CollapsingMergeTree collapsing...' as status;
SELECT 'CollapsingMergeTree collapsing 실행 중...' as status_kr;
SELECT now() as start_time;

-- Insert sign=-1 for records to delete
-- 삭제할 데이터에 대해 sign=-1 INSERT
INSERT INTO delete_test.collapsing_merge_table
SELECT 
    user_id,
    event_time,
    event_type,
    value,
    status,
    -1 as sign  -- Delete (negative sign) / 삭제 (음수 sign)
FROM delete_test.collapsing_merge_table
WHERE user_id % 10 = 0 AND sign = 1;

SELECT 'CollapsingMergeTree collapsing completed' as status;
SELECT 'CollapsingMergeTree collapsing 완료' as status_kr;
SELECT now() as end_time;

-- Verify inserted negative signs
-- 삽입된 negative sign 확인
SELECT 
    'Negative signs inserted' as info,
    countIf(sign = -1) as negative_sign_count
FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- Post-deletion status check
-- 삭제 후 상태 확인
-- ============================================================================

SELECT 'After DELETE operations' as checkpoint;
SELECT '삭제 작업 후' as checkpoint_kr;

-- ALTER DELETE table (physical delete - changes after mutation completes)
-- ALTER DELETE 테이블 (물리적 삭제 - mutation 완료 후에 변경됨)
SELECT 
    'alter_delete_table' as table_name,
    count() as visible_rows,
    'Physical delete (may be pending)' as note,
    '물리적 삭제 (보류 중일 수 있음)' as note_kr
FROM delete_test.alter_delete_table

UNION ALL

-- ReplacingMergeTree (without FINAL)
-- ReplacingMergeTree (FINAL 없이)
SELECT 
    'replacing_merge_table (No FINAL)',
    countIf(is_deleted = 0),
    'Inaccurate without FINAL',
    'FINAL 없이는 부정확'
FROM delete_test.replacing_merge_table

UNION ALL

-- ReplacingMergeTree (with FINAL)
-- ReplacingMergeTree (FINAL 사용)
SELECT 
    'replacing_merge_table (FINAL)',
    countIf(is_deleted = 0),
    'Accurate with FINAL',
    'FINAL 사용 시 정확'
FROM delete_test.replacing_merge_table FINAL

UNION ALL

-- CollapsingMergeTree (raw count)
-- CollapsingMergeTree (raw 카운트)
SELECT 
    'collapsing_merge_table (Raw)',
    toUInt64(countIf(sign = 1)),
    'Inaccurate raw count',
    '부정확한 raw 카운트'
FROM delete_test.collapsing_merge_table

UNION ALL

-- CollapsingMergeTree (sum(sign))
-- CollapsingMergeTree (sum(sign) 사용)
SELECT 
    'collapsing_merge_table (Net)',
    toUInt64(sum(sign)),
    'Accurate with sum(sign)',
    'sum(sign) 사용 시 정확'
FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- Detailed statistics
-- 상세 통계
-- ============================================================================

SELECT 'Detailed Statistics / 상세 통계' as section;

-- ReplacingMergeTree version distribution
-- ReplacingMergeTree 버전 분포
SELECT 
    'ReplacingMergeTree version distribution' as metric,
    is_deleted,
    count() as count,
    countDistinct(version) as version_count,
    round(count() * 100.0 / (SELECT count() FROM delete_test.replacing_merge_table), 1) as percentage
FROM delete_test.replacing_merge_table
GROUP BY is_deleted;

-- CollapsingMergeTree sign distribution
-- CollapsingMergeTree sign 분포
SELECT 
    'CollapsingMergeTree sign distribution' as metric,
    sign,
    count() as count,
    round(count() * 100.0 / (SELECT count() FROM delete_test.collapsing_merge_table), 1) as percentage
FROM delete_test.collapsing_merge_table
GROUP BY sign;

-- Storage comparison after deletion
-- 삭제 후 스토리지 비교
SELECT 
    'Storage Usage After Deletion' as metric,
    table,
    sum(rows) as total_rows,
    count() as parts_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table
ORDER BY table;

-- ============================================================================
-- Completion message
-- 완료 메시지
-- ============================================================================
SELECT 'DELETE operations completed! Check mutation status for ALTER DELETE.' as status;
SELECT 'DELETE 작업 완료! ALTER DELETE의 mutation 상태를 확인하세요.' as status_kr;
