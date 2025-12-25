-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Analyze Results
-- ClickHouse Index Granularity Point Query 벤치마크 - 결과 분석
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Analyze query performance and compare results
-- 목적: 쿼리 성능 분석 및 결과 비교
-- ============================================================================

-- Ensure logs are flushed
-- 로그가 플러시되었는지 확인
SYSTEM FLUSH LOGS;

-- ============================================================================
-- 1. Recent Query Performance Summary
-- 1. 최근 쿼리 성능 요약
-- ============================================================================

SELECT '=== Recent Query Performance Summary / 최근 쿼리 성능 요약 ===' AS info;

SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_size,
    result_rows,
    substring(query, 1, 100) AS query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%granularity_test.player_g%'
  AND query NOT LIKE '%system%'
  AND query NOT LIKE '%EXPLAIN%'
  AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 30;

-- ============================================================================
-- 2. Performance Comparison by Granularity (Point Queries)
-- 2. Granularity별 성능 비교 (Point Query)
-- ============================================================================

SELECT '=== Performance Comparison by Granularity / Granularity별 성능 비교 ===' AS info;

SELECT
    CASE
        WHEN query LIKE '%player_g256%' THEN 'G256'
        WHEN query LIKE '%player_g1024%' THEN 'G1024'
        WHEN query LIKE '%player_g4096%' THEN 'G4096'
        WHEN query LIKE '%player_g8192%' THEN 'G8192'
    END AS granularity,
    count() AS query_count,
    round(avg(query_duration_ms), 2) AS avg_duration_ms,
    round(min(query_duration_ms), 2) AS min_duration_ms,
    round(max(query_duration_ms), 2) AS max_duration_ms,
    round(avg(read_rows), 0) AS avg_read_rows,
    formatReadableSize(round(avg(read_bytes), 0)) AS avg_read_size
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%granularity_test.player_g%'
  AND query LIKE '%player_id%'
  AND query NOT LIKE '%system%'
  AND query NOT LIKE '%EXPLAIN%'
  AND query NOT LIKE '%INSERT%'
  AND event_time > now() - INTERVAL 1 HOUR
GROUP BY granularity
ORDER BY granularity;

-- ============================================================================
-- 3. Relative Performance Analysis
-- 3. 상대 성능 분석
-- ============================================================================

SELECT '=== Relative Performance Analysis / 상대 성능 분석 ===' AS info;

WITH performance_data AS (
    SELECT
        CASE
            WHEN query LIKE '%player_g256%' THEN 'G256'
            WHEN query LIKE '%player_g1024%' THEN 'G1024'
            WHEN query LIKE '%player_g4096%' THEN 'G4096'
            WHEN query LIKE '%player_g8192%' THEN 'G8192'
        END AS granularity,
        avg(query_duration_ms) AS avg_duration_ms,
        avg(read_rows) AS avg_read_rows
    FROM system.query_log
    WHERE type = 'QueryFinish'
      AND query LIKE '%granularity_test.player_g%'
      AND query LIKE '%player_id%'
      AND query NOT LIKE '%system%'
      AND query NOT LIKE '%EXPLAIN%'
      AND query NOT LIKE '%INSERT%'
      AND event_time > now() - INTERVAL 1 HOUR
    GROUP BY granularity
),
baseline AS (
    SELECT
        avg_duration_ms AS baseline_duration,
        avg_read_rows AS baseline_rows
    FROM performance_data
    WHERE granularity = 'G8192'
)
SELECT
    p.granularity,
    round(p.avg_duration_ms, 2) AS avg_duration_ms,
    round(p.avg_read_rows, 0) AS avg_read_rows,
    round(p.avg_duration_ms / b.baseline_duration, 2) AS duration_ratio,
    round(p.avg_read_rows / b.baseline_rows, 2) AS read_rows_ratio,
    CASE
        WHEN p.avg_duration_ms < b.baseline_duration THEN
            concat('✓ ', toString(round((1 - p.avg_duration_ms / b.baseline_duration) * 100, 1)), '% faster')
        WHEN p.avg_duration_ms > b.baseline_duration THEN
            concat('✗ ', toString(round((p.avg_duration_ms / b.baseline_duration - 1) * 100, 1)), '% slower')
        ELSE '= Same'
    END AS performance_vs_baseline
FROM performance_data p
CROSS JOIN baseline b
ORDER BY p.granularity;

-- ============================================================================
-- 4. Query Type Performance Breakdown
-- 4. 쿼리 타입별 성능 분석
-- ============================================================================

SELECT '=== Query Type Performance Breakdown / 쿼리 타입별 성능 분석 ===' AS info;

SELECT
    CASE
        WHEN query LIKE '%WHERE player_id = %' THEN 'Single Point Query'
        WHEN query LIKE '%WHERE player_id IN%' THEN 'Multiple Point Query (IN)'
        WHEN query LIKE '%WHERE player_id BETWEEN%' THEN 'Range Query'
        ELSE 'Other'
    END AS query_type,
    CASE
        WHEN query LIKE '%player_g256%' THEN 'G256'
        WHEN query LIKE '%player_g1024%' THEN 'G1024'
        WHEN query LIKE '%player_g4096%' THEN 'G4096'
        WHEN query LIKE '%player_g8192%' THEN 'G8192'
    END AS granularity,
    count() AS query_count,
    round(avg(query_duration_ms), 2) AS avg_duration_ms,
    round(avg(read_rows), 0) AS avg_read_rows
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%granularity_test.player_g%'
  AND query NOT LIKE '%system%'
  AND query NOT LIKE '%EXPLAIN%'
  AND query NOT LIKE '%INSERT%'
  AND event_time > now() - INTERVAL 1 HOUR
GROUP BY query_type, granularity
ORDER BY query_type, granularity;

-- ============================================================================
-- 5. Storage vs Performance Trade-off
-- 5. 스토리지 vs 성능 트레이드오프
-- ============================================================================

SELECT '=== Storage vs Performance Trade-off / 스토리지 vs 성능 트레이드오프 ===' AS info;

WITH storage_data AS (
    SELECT
        name AS table_name,
        extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity,
        total_marks,
        total_bytes / 1024.0 / 1024.0 AS size_mb
    FROM system.tables
    WHERE database = 'granularity_test'
      AND name LIKE 'player_g%'
),
performance_data AS (
    SELECT
        CASE
            WHEN query LIKE '%player_g256%' THEN '256'
            WHEN query LIKE '%player_g1024%' THEN '1024'
            WHEN query LIKE '%player_g4096%' THEN '4096'
            WHEN query LIKE '%player_g8192%' THEN '8192'
        END AS granularity,
        avg(query_duration_ms) AS avg_duration_ms
    FROM system.query_log
    WHERE type = 'QueryFinish'
      AND query LIKE '%granularity_test.player_g%'
      AND query LIKE '%player_id%'
      AND query NOT LIKE '%system%'
      AND query NOT LIKE '%EXPLAIN%'
      AND query NOT LIKE '%INSERT%'
      AND event_time > now() - INTERVAL 1 HOUR
    GROUP BY granularity
)
SELECT
    s.granularity,
    s.total_marks,
    round(s.size_mb, 2) AS table_size_mb,
    round(p.avg_duration_ms, 2) AS avg_query_ms,
    round(s.size_mb / p.avg_duration_ms, 2) AS mb_per_ms_ratio
FROM storage_data s
LEFT JOIN performance_data p ON s.granularity = p.granularity
ORDER BY CAST(s.granularity AS UInt32);

-- ============================================================================
-- 6. Recommendations Summary
-- 6. 권장사항 요약
-- ============================================================================

SELECT '=== Recommendations Summary / 권장사항 요약 ===' AS info;

SELECT
    '1. Best for Point Queries / Point Query에 최적' AS recommendation_type,
    'Use smaller granularity (256 or 1024) for frequent point queries' AS recommendation_en,
    '빈번한 point query를 위해서는 작은 granularity (256 또는 1024)를 사용하세요' AS recommendation_ko
UNION ALL
SELECT
    '2. Best for Scan Queries / 스캔 쿼리에 최적',
    'Use larger granularity (4096 or 8192) for full table scans',
    '전체 테이블 스캔을 위해서는 큰 granularity (4096 또는 8192)를 사용하세요'
UNION ALL
SELECT
    '3. Storage Trade-off / 스토리지 트레이드오프',
    'Smaller granularity increases index size but improves point query performance',
    '작은 granularity는 인덱스 크기를 증가시키지만 point query 성능을 향상시킵니다'
UNION ALL
SELECT
    '4. Balanced Approach / 균형잡힌 접근',
    'For mixed workloads, granularity 1024-4096 offers good balance',
    '혼합 워크로드의 경우 granularity 1024-4096이 좋은 균형을 제공합니다';

SELECT '✓ Analysis completed / 분석 완료';
