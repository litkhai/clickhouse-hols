-- ============================================================================
-- ClickHouse DELETE Mechanism Benchmark - Comprehensive Report
-- ClickHouse DELETE 메커니즘 벤치마크 - 종합 리포트 생성
-- ============================================================================
-- Created: 2025-12-01
-- 작성일: 2025-12-01
-- Purpose: Generate comprehensive report summarizing all test results
-- 목적: 모든 테스트 결과를 종합하여 리포트 생성
-- ============================================================================

SELECT '================================================' as separator;
SELECT 'ClickHouse DELETE Mechanism Benchmark Report' as title;
SELECT 'ClickHouse DELETE 메커니즘 벤치마크 리포트' as title_kr;
SELECT '================================================' as separator;

-- ============================================================================
-- 1. Table Status Summary
-- 1. 테이블 상태 요약
-- ============================================================================

SELECT '=== 1. Table Status Summary / 테이블 상태 요약 ===' as section;

SELECT 
    table,
    sum(rows) as total_rows,
    count() as parts_count,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) as compression_ratio,
    formatReadableSize(sum(primary_key_bytes_in_memory)) as pk_memory,
    formatReadableSize(sum(bytes_on_disk)) as disk_size
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table
ORDER BY table;

-- ============================================================================
-- 2. Data Accuracy Comparison
-- 2. 데이터 정확성 비교
-- ============================================================================

SELECT '=== 2. Data Accuracy Comparison / 데이터 정확성 비교 ===' as section;

SELECT 
    'ALTER_DELETE' as method,
    'ALTER_DELETE' as method_kr,
    count() as visible_rows,
    count() as stored_rows,
    0 as overhead_pct,
    'Accurate / 정확' as accuracy
FROM delete_test.alter_delete_table

UNION ALL

SELECT 
    'REPLACING_NO_FINAL',
    'REPLACING (FINAL 없음)',
    countIf(is_deleted = 0),
    count(),
    round((count() - countIf(is_deleted = 0)) * 100.0 / count(), 1),
    'Inaccurate / 부정확'
FROM delete_test.replacing_merge_table

UNION ALL

SELECT 
    'REPLACING_FINAL',
    'REPLACING (FINAL)',
    countIf(is_deleted = 0),
    count(),
    round((count() - countIf(is_deleted = 0)) * 100.0 / count(), 1),
    'Accurate / 정확'
FROM delete_test.replacing_merge_table FINAL

UNION ALL

SELECT 
    'COLLAPSING_RAW',
    'COLLAPSING (Raw count)',
    toUInt64(countIf(sign = 1)),
    count(),
    round((count() - countIf(sign = 1)) * 100.0 / count(), 1),
    'Inaccurate / 부정확'
FROM delete_test.collapsing_merge_table

UNION ALL

SELECT 
    'COLLAPSING_NET',
    'COLLAPSING (sum(sign))',
    toUInt64(sum(sign)),
    count(),
    round((count() - sum(sign)) * 100.0 / count(), 1),
    'Accurate / 정확'
FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- 3. Query Performance Summary
-- 3. 쿼리 성능 요약
-- ============================================================================

SELECT '=== 3. Query Performance Summary / 쿼리 성능 요약 ===' as section;

WITH query_metrics AS (
    SELECT 
        CASE 
            WHEN query LIKE '%alter_delete_table%' AND query LIKE '%GROUP BY%' THEN 'ALTER_DELETE'
            WHEN query LIKE '%replacing_merge_table FINAL%' AND query LIKE '%GROUP BY%' THEN 'REPLACING_FINAL'
            WHEN query LIKE '%replacing_merge_table%' AND query NOT LIKE '%FINAL%' AND query LIKE '%GROUP BY%' THEN 'REPLACING_NO_FINAL'
            WHEN query LIKE '%collapsing_merge_table%' AND query LIKE '%GROUP BY%' THEN 'COLLAPSING'
        END as query_type,
        query_duration_ms,
        read_rows,
        read_bytes,
        memory_usage
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 10 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%delete_test%'
        AND query NOT LIKE '%system.%'
        AND query LIKE '%GROUP BY%'
)
SELECT 
    query_type,
    count() as execution_count,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(min(query_duration_ms), 2) as min_duration_ms,
    round(max(query_duration_ms), 2) as max_duration_ms,
    round(avg(read_rows), 0) as avg_read_rows,
    formatReadableSize(round(avg(read_bytes), 0)) as avg_read_bytes,
    formatReadableSize(round(avg(memory_usage), 0)) as avg_memory_usage
FROM query_metrics
WHERE query_type IS NOT NULL
GROUP BY query_type
ORDER BY avg_duration_ms;

-- ============================================================================
-- 4. Relative Performance (vs ALTER DELETE)
-- 4. 상대 성능 비교 (ALTER DELETE 기준)
-- ============================================================================

SELECT '=== 4. Relative Performance (vs ALTER DELETE) / 상대 성능 비교 ===' as section;

WITH baseline AS (
    SELECT avg(query_duration_ms) as baseline_duration
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 10 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%alter_delete_table%'
        AND query LIKE '%GROUP BY%'
        AND query NOT LIKE '%system.%'
),
query_metrics AS (
    SELECT 
        CASE 
            WHEN query LIKE '%alter_delete_table%' THEN 'ALTER_DELETE'
            WHEN query LIKE '%replacing_merge_table FINAL%' THEN 'REPLACING_FINAL'
            WHEN query LIKE '%collapsing_merge_table%' THEN 'COLLAPSING'
        END as query_type,
        query_duration_ms
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 10 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%delete_test%'
        AND query NOT LIKE '%system.%'
        AND query LIKE '%GROUP BY%'
)
SELECT 
    qm.query_type,
    round(avg(qm.query_duration_ms), 2) as avg_duration_ms,
    round(avg(qm.query_duration_ms) / b.baseline_duration, 2) as relative_to_baseline,
    concat('+', toString(round((avg(qm.query_duration_ms) / b.baseline_duration - 1) * 100, 0)), '%') as overhead
FROM query_metrics qm, baseline b
WHERE qm.query_type IS NOT NULL
GROUP BY qm.query_type, b.baseline_duration
ORDER BY relative_to_baseline;

-- ============================================================================
-- 5. Storage Efficiency Comparison
-- 5. 스토리지 효율성 비교
-- ============================================================================

SELECT '=== 5. Storage Efficiency Comparison / 스토리지 효율성 비교 ===' as section;

WITH baseline AS (
    SELECT sum(data_compressed_bytes) as baseline_size
    FROM system.parts
    WHERE database = 'delete_test' 
      AND table = 'alter_delete_table' 
      AND active
)
SELECT 
    p.table,
    formatReadableSize(sum(p.data_compressed_bytes)) as compressed_size,
    round(sum(p.data_compressed_bytes) / b.baseline_size, 2) as relative_to_baseline,
    concat('+', toString(round((sum(p.data_compressed_bytes) / b.baseline_size - 1) * 100, 0)), '%') as overhead
FROM system.parts p, baseline b
WHERE p.database = 'delete_test' AND p.active
GROUP BY p.table, b.baseline_size
ORDER BY relative_to_baseline;

-- ============================================================================
-- 6. Mutation Status (ALTER DELETE)
-- 6. Mutation 상태 (ALTER DELETE)
-- ============================================================================

SELECT '=== 6. Mutation Status (ALTER DELETE) / Mutation 상태 ===' as section;

SELECT 
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    CASE 
        WHEN is_done = 1 THEN 'Completed / 완료'
        WHEN is_done = 0 THEN 'In Progress / 진행 중'
        ELSE 'Unknown / 알 수 없음'
    END as status,
    latest_fail_reason
FROM system.mutations
WHERE database = 'delete_test' 
  AND table = 'alter_delete_table'
ORDER BY create_time DESC
LIMIT 5;

-- ============================================================================
-- 7. Parts Distribution
-- 7. Parts 분포
-- ============================================================================

SELECT '=== 7. Parts Distribution / Parts 분포 ===' as section;

SELECT 
    table,
    partition,
    count() as parts_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table, partition
ORDER BY table, partition;

-- ============================================================================
-- 8. Memory Usage Comparison
-- 8. 메모리 사용량 비교
-- ============================================================================

SELECT '=== 8. Memory Usage Comparison / 메모리 사용량 비교 ===' as section;

WITH memory_metrics AS (
    SELECT 
        CASE 
            WHEN query LIKE '%alter_delete_table%' THEN 'ALTER_DELETE'
            WHEN query LIKE '%replacing_merge_table FINAL%' THEN 'REPLACING_FINAL'
            WHEN query LIKE '%collapsing_merge_table%' THEN 'COLLAPSING'
        END as query_type,
        memory_usage
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 10 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%delete_test%'
        AND query NOT LIKE '%system.%'
        AND query LIKE '%GROUP BY%'
)
SELECT 
    query_type,
    formatReadableSize(round(avg(memory_usage), 0)) as avg_memory,
    formatReadableSize(round(min(memory_usage), 0)) as min_memory,
    formatReadableSize(round(max(memory_usage), 0)) as max_memory
FROM memory_metrics
WHERE query_type IS NOT NULL
GROUP BY query_type
ORDER BY avg(memory_usage);

-- ============================================================================
-- 9. Final Recommendations
-- 9. 최종 권장사항
-- ============================================================================

SELECT '=== 9. Recommendations / 권장사항 ===' as section;

SELECT 
    'Performance Priority / 성능 우선' as scenario,
    'ALTER DELETE' as recommended_method,
    'Fastest queries, lowest storage, best for batch deletes' as reason_en,
    '가장 빠른 쿼리, 최소 스토리지, 배치 삭제에 최적' as reason_kr

UNION ALL

SELECT 
    'Real-time Deletes / 실시간 삭제',
    'CollapsingMergeTree',
    'Fast deletes, good query performance, balanced approach',
    '빠른 삭제, 좋은 쿼리 성능, 균형잡힌 접근'

UNION ALL

SELECT 
    'Audit Trail Required / 감사 추적 필요',
    'ReplacingMergeTree',
    'Complete history, rollback support, compliance ready',
    '완전한 히스토리, 롤백 지원, 규제 준수'

UNION ALL

SELECT 
    'High Frequency Updates / 고빈도 업데이트',
    'CollapsingMergeTree',
    'Optimized for incremental updates, efficient aggregation',
    'Incremental update에 최적화, 효율적인 집계'

UNION ALL

SELECT 
    'Low Delete Frequency / 낮은 삭제 빈도',
    'ALTER DELETE',
    'Best query performance, minimal storage overhead',
    '최고의 쿼리 성능, 최소 스토리지 오버헤드';

-- ============================================================================
-- 10. Quick Reference Table
-- 10. 빠른 참조 테이블
-- ============================================================================

SELECT '=== 10. Quick Reference / 빠른 참조 ===' as section;

SELECT 
    'Metric / 메트릭' as metric,
    'ALTER DELETE' as alter_delete,
    'ReplacingMergeTree' as replacing,
    'CollapsingMergeTree' as collapsing,
    'Winner / 우승자' as winner
    
UNION ALL SELECT '--- Performance ---', '---', '---', '---', '---'
UNION ALL SELECT 'Query Speed / 쿼리 속도', '★★★★★ (23.5ms)', '★★☆☆☆ (90ms)', '★★★★☆ (27.5ms)', 'ALTER'
UNION ALL SELECT 'Delete Speed / 삭제 속도', '★★★☆☆ (34.8ms*)', '★★★☆☆ (530ms)', '★★★★☆ (435ms)', 'COLLAPSING'
    
UNION ALL SELECT '--- Resources ---', '---', '---', '---', '---'
UNION ALL SELECT 'Storage / 스토리지', '★★★★★ (7.11 MiB)', '★★☆☆☆ (9.56 MiB)', '★★★☆☆ (9.32 MiB)', 'ALTER'
UNION ALL SELECT 'Memory / 메모리', '★★★★★ (24.94 MiB)', '★★☆☆☆ (75.66 MiB)', '★★★★☆ (32.54 MiB)', 'ALTER'
UNION ALL SELECT 'Parts Count / Parts 수', '★★★★★ (13)', '★★☆☆☆ (26)', '★★☆☆☆ (26)', 'ALTER'
    
UNION ALL SELECT '--- Features ---', '---', '---', '---', '---'
UNION ALL SELECT 'Real-time / 실시간', '❌ Async', '✅ Instant', '✅ Instant', 'REPLACING/COLLAPSING'
UNION ALL SELECT 'Rollback / 롤백', '❌ No', '✅ Yes', '❌ Difficult', 'REPLACING'
UNION ALL SELECT 'Audit Trail / 감사 추적', '❌ No', '✅ Yes', '❌ Limited', 'REPLACING'
UNION ALL SELECT 'Query Complexity / 쿼리 복잡도', '🟢 Simple', '🟡 FINAL needed', '🔴 sum(sign)', 'ALTER';

-- ============================================================================
-- Completion message
-- 완료 메시지
-- ============================================================================

SELECT '================================================' as separator;
SELECT 'Benchmark Report Generated Successfully!' as status;
SELECT '벤치마크 리포트 생성 완료!' as status_kr;
SELECT '================================================' as separator;
SELECT concat('Generated at / 생성 시간: ', toString(now())) as timestamp;
