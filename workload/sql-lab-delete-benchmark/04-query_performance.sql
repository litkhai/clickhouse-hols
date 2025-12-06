-- ============================================================================
-- ClickHouse DELETE Mechanism Benchmark - Query Performance Test
-- ClickHouse DELETE 메커니즘 벤치마크 - 쿼리 성능 테스트
-- ============================================================================
-- Created: 2025-12-01
-- 작성일: 2025-12-01
-- Purpose: Compare SELECT query performance for each DELETE method
-- 목적: 각 DELETE 방식의 SELECT 쿼리 성능 비교
-- ============================================================================

-- ============================================================================
-- Preparation: Verify query log is enabled
-- 준비: 쿼리 로그 활성화 확인
-- ============================================================================
-- Use system.query_log for performance measurement
-- system.query_log를 사용하여 성능 측정
-- ============================================================================

SELECT 'Starting query performance benchmark...' as status;
SELECT '쿼리 성능 벤치마크 시작...' as status_kr;

-- ============================================================================
-- Test 1: Simple COUNT Query
-- 테스트 1: 단순 COUNT 쿼리
-- ============================================================================

SELECT '=== Test 1: Simple COUNT Query / 테스트 1: 단순 COUNT 쿼리 ===' as test_name;

-- 1.1 ALTER DELETE
SELECT 'ALTER DELETE - Simple COUNT' as test;
SELECT count() as row_count FROM delete_test.alter_delete_table;

-- 1.2 ReplacingMergeTree (No FINAL)
SELECT 'REPLACING (No FINAL) - Simple COUNT / 부정확한 결과' as test;
SELECT count() as row_count FROM delete_test.replacing_merge_table WHERE is_deleted = 0;

-- 1.3 ReplacingMergeTree (FINAL)
SELECT 'REPLACING (FINAL) - Simple COUNT / 정확한 결과' as test;
SELECT count() as row_count FROM delete_test.replacing_merge_table FINAL WHERE is_deleted = 0;

-- 1.4 CollapsingMergeTree
SELECT 'COLLAPSING - Simple COUNT' as test;
SELECT sum(sign) as row_count FROM delete_test.collapsing_merge_table;

-- ============================================================================
-- Test 2: Aggregation by Event Type
-- 테스트 2: Event Type별 집계 쿼리
-- ============================================================================

SELECT '=== Test 2: Aggregation by Event Type / 테스트 2: Event Type별 집계 ===' as test_name;

-- 2.1 ALTER DELETE
SELECT 'ALTER DELETE - Event Type Aggregation' as test;
SELECT 
    event_type,
    count() as cnt,
    round(avg(value), 2) as avg_value,
    round(sum(value), 2) as sum_value,
    round(min(value), 2) as min_value,
    round(max(value), 2) as max_value
FROM delete_test.alter_delete_table
GROUP BY event_type
ORDER BY event_type;

-- 2.2 ReplacingMergeTree (No FINAL) - Inaccurate / 부정확
SELECT 'REPLACING (No FINAL) - Event Type Aggregation / 부정확' as test;
SELECT 
    event_type,
    count() as cnt,
    round(avg(value), 2) as avg_value,
    round(sum(value), 2) as sum_value,
    round(min(value), 2) as min_value,
    round(max(value), 2) as max_value
FROM delete_test.replacing_merge_table
WHERE is_deleted = 0
GROUP BY event_type
ORDER BY event_type;

-- 2.3 ReplacingMergeTree (FINAL) - Accurate / 정확
SELECT 'REPLACING (FINAL) - Event Type Aggregation / 정확' as test;
SELECT 
    event_type,
    count() as cnt,
    round(avg(value), 2) as avg_value,
    round(sum(value), 2) as sum_value,
    round(min(value), 2) as min_value,
    round(max(value), 2) as max_value
FROM delete_test.replacing_merge_table FINAL
WHERE is_deleted = 0
GROUP BY event_type
ORDER BY event_type;

-- 2.4 CollapsingMergeTree
SELECT 'COLLAPSING - Event Type Aggregation' as test;
SELECT 
    event_type,
    sum(sign) as cnt,
    round(sum(value * sign) / nullIf(sum(sign), 0), 2) as avg_value,
    round(sum(value * sign), 2) as sum_value,
    round(minIf(value, sign > 0), 2) as min_value,
    round(maxIf(value, sign > 0), 2) as max_value
FROM delete_test.collapsing_merge_table
GROUP BY event_type
HAVING sum(sign) > 0
ORDER BY event_type;

-- ============================================================================
-- Test 3: Time-series Aggregation (Recent 1 Month)
-- 테스트 3: 시계열 집계 쿼리 (최근 1개월)
-- ============================================================================

SELECT '=== Test 3: Time-series Aggregation / 테스트 3: 시계열 집계 ===' as test_name;

-- 3.1 ALTER DELETE
SELECT 'ALTER DELETE - Time-series' as test;
SELECT 
    toStartOfDay(event_time) as day,
    event_type,
    count() as cnt
FROM delete_test.alter_delete_table
WHERE event_time >= now() - INTERVAL 30 DAY
GROUP BY day, event_type
ORDER BY day, event_type
LIMIT 20;

-- 3.2 ReplacingMergeTree (FINAL)
SELECT 'REPLACING (FINAL) - Time-series' as test;
SELECT 
    toStartOfDay(event_time) as day,
    event_type,
    count() as cnt
FROM delete_test.replacing_merge_table FINAL
WHERE event_time >= now() - INTERVAL 30 DAY
  AND is_deleted = 0
GROUP BY day, event_type
ORDER BY day, event_type
LIMIT 20;

-- 3.3 CollapsingMergeTree
SELECT 'COLLAPSING - Time-series' as test;
SELECT 
    toStartOfDay(event_time) as day,
    event_type,
    sum(sign) as cnt
FROM delete_test.collapsing_merge_table
WHERE event_time >= now() - INTERVAL 30 DAY
GROUP BY day, event_type
HAVING sum(sign) > 0
ORDER BY day, event_type
LIMIT 20;

-- ============================================================================
-- Test 4: Complex Filter + Aggregation Query
-- 테스트 4: 복잡한 필터 + 집계 쿼리
-- ============================================================================

SELECT '=== Test 4: Complex Filter + Aggregation / 테스트 4: 복잡한 쿼리 ===' as test_name;

-- 4.1 ALTER DELETE
SELECT 'ALTER DELETE - Complex Query' as test;
SELECT 
    status,
    event_type,
    count() as cnt,
    round(avg(value), 2) as avg_value,
    round(min(value), 2) as min_value,
    round(max(value), 2) as max_value,
    round(stddevPop(value), 2) as stddev_value
FROM delete_test.alter_delete_table
WHERE value > 5.0
  AND event_time >= now() - INTERVAL 180 DAY
GROUP BY status, event_type
ORDER BY cnt DESC
LIMIT 10;

-- 4.2 ReplacingMergeTree (FINAL)
SELECT 'REPLACING (FINAL) - Complex Query' as test;
SELECT 
    status,
    event_type,
    count() as cnt,
    round(avg(value), 2) as avg_value,
    round(min(value), 2) as min_value,
    round(max(value), 2) as max_value,
    round(stddevPop(value), 2) as stddev_value
FROM delete_test.replacing_merge_table FINAL
WHERE value > 5.0
  AND event_time >= now() - INTERVAL 180 DAY
  AND is_deleted = 0
GROUP BY status, event_type
ORDER BY cnt DESC
LIMIT 10;

-- 4.3 CollapsingMergeTree
SELECT 'COLLAPSING - Complex Query' as test;
SELECT 
    status,
    event_type,
    sum(sign) as cnt,
    round(sum(value * sign) / nullIf(sum(sign), 0), 2) as avg_value,
    round(minIf(value, sign > 0), 2) as min_value,
    round(maxIf(value, sign > 0), 2) as max_value,
    round(stddevPopIf(value, sign > 0), 2) as stddev_value
FROM delete_test.collapsing_merge_table
WHERE value > 5.0
  AND event_time >= now() - INTERVAL 180 DAY
GROUP BY status, event_type
HAVING sum(sign) > 0
ORDER BY cnt DESC
LIMIT 10;

-- ============================================================================
-- Test 5: User-level Aggregation
-- 테스트 5: 사용자별 집계
-- ============================================================================

SELECT '=== Test 5: User-level Aggregation / 테스트 5: 사용자별 집계 ===' as test_name;

-- 5.1 ALTER DELETE
SELECT 'ALTER DELETE - User Aggregation' as test;
SELECT 
    user_id,
    count() as event_count,
    countDistinct(event_type) as unique_events,
    round(avg(value), 2) as avg_value
FROM delete_test.alter_delete_table
WHERE user_id < 1000
GROUP BY user_id
ORDER BY event_count DESC
LIMIT 10;

-- 5.2 ReplacingMergeTree (FINAL)
SELECT 'REPLACING (FINAL) - User Aggregation' as test;
SELECT 
    user_id,
    count() as event_count,
    countDistinct(event_type) as unique_events,
    round(avg(value), 2) as avg_value
FROM delete_test.replacing_merge_table FINAL
WHERE user_id < 1000
  AND is_deleted = 0
GROUP BY user_id
ORDER BY event_count DESC
LIMIT 10;

-- 5.3 CollapsingMergeTree
SELECT 'COLLAPSING - User Aggregation' as test;
SELECT 
    user_id,
    sum(sign) as event_count,
    uniqExactIf(event_type, sign > 0) as unique_events,
    round(sum(value * sign) / nullIf(sum(sign), 0), 2) as avg_value
FROM delete_test.collapsing_merge_table
WHERE user_id < 1000
GROUP BY user_id
HAVING sum(sign) > 0
ORDER BY event_count DESC
LIMIT 10;

-- ============================================================================
-- Performance Metrics Collection (Recent executed queries)
-- 성능 메트릭 수집 (최근 실행한 쿼리들)
-- ============================================================================

SELECT '=== Query Performance Summary / 쿼리 성능 요약 ===' as summary;

-- Recent test query performance metrics
-- 최근 실행된 테스트 쿼리들의 성능 메트릭
WITH query_classification AS (
    SELECT 
        CASE 
            WHEN query LIKE '%alter_delete_table%' THEN 'ALTER_DELETE'
            WHEN query LIKE '%replacing_merge_table FINAL%' THEN 'REPLACING_FINAL'
            WHEN query LIKE '%replacing_merge_table%' AND query NOT LIKE '%FINAL%' THEN 'REPLACING_NO_FINAL'
            WHEN query LIKE '%collapsing_merge_table%' THEN 'COLLAPSING'
            ELSE 'OTHER'
        END as query_type,
        query_duration_ms,
        read_rows,
        read_bytes,
        memory_usage,
        result_rows
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 5 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%delete_test%'
        AND query NOT LIKE '%system.%'
        AND (query LIKE '%GROUP BY%' OR query LIKE '%count()%' OR query LIKE '%sum(sign)%')
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
FROM query_classification
WHERE query_type != 'OTHER'
GROUP BY query_type
ORDER BY avg_duration_ms;

-- ============================================================================
-- Relative Performance Comparison
-- 상대 성능 비교
-- ============================================================================

SELECT '=== Relative Performance (vs ALTER DELETE) / 상대 성능 ===' as summary;

WITH baseline AS (
    SELECT avg(query_duration_ms) as baseline_duration
    FROM system.query_log
    WHERE event_time >= now() - INTERVAL 5 MINUTE
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
    WHERE event_time >= now() - INTERVAL 5 MINUTE
        AND type = 'QueryFinish'
        AND query LIKE '%delete_test%'
        AND query NOT LIKE '%system.%'
        AND query LIKE '%GROUP BY%'
)
SELECT 
    qm.query_type,
    round(avg(qm.query_duration_ms), 2) as avg_duration_ms,
    round(avg(qm.query_duration_ms) / b.baseline_duration, 2) as relative_speed,
    concat(round((avg(qm.query_duration_ms) / b.baseline_duration - 1) * 100, 0), '%') as overhead_pct
FROM query_metrics qm, baseline b
WHERE qm.query_type IS NOT NULL
GROUP BY qm.query_type, b.baseline_duration
ORDER BY relative_speed;

-- ============================================================================
-- Completion message
-- 완료 메시지
-- ============================================================================
SELECT 'Query performance benchmark completed!' as status;
SELECT '쿼리 성능 벤치마크 완료!' as status_kr;
