-- ============================================================================
-- MV vs RMV 테스트: 결과 분석 쿼리
-- Result Analysis Queries for MV vs RMV Test
-- ============================================================================
-- 사용법 / Usage:
-- <SESSION_ID>를 실제 세션 ID로 교체하세요
-- Replace <SESSION_ID> with your actual session ID
-- ============================================================================

-- ============================================================================
-- 1. 전체 리소스 사용량 비교 / Overall Resource Usage Comparison
-- ============================================================================
SELECT
    metric_source,
    sum(query_count) AS total_queries,
    round(sum(query_duration_ms) / 1000, 2) AS total_duration_sec,
    formatReadableSize(sum(memory_usage_bytes)) AS total_memory,
    formatReadableSize(max(peak_memory_usage_bytes)) AS peak_memory,
    sum(read_rows) AS total_read_rows,
    formatReadableSize(sum(read_bytes)) AS total_read_bytes,
    sum(written_rows) AS total_written_rows,
    formatReadableSize(sum(written_bytes)) AS total_written_bytes
FROM mv_vs_rmv.resource_metrics
WHERE session_id = '<SESSION_ID>'
GROUP BY metric_source
ORDER BY metric_source
FORMAT Vertical;


-- ============================================================================
-- 2. 시간대별 리소스 추이 / Resource Trends Over Time
-- ============================================================================
SELECT
    toStartOfMinute(collected_at) AS minute,
    metric_source,
    sum(query_count) AS queries,
    sum(query_duration_ms) AS duration_ms,
    formatReadableSize(max(peak_memory_usage_bytes)) AS peak_memory,
    sum(written_rows) AS written_rows
FROM mv_vs_rmv.resource_metrics
WHERE session_id = '<SESSION_ID>'
GROUP BY minute, metric_source
ORDER BY minute, metric_source
FORMAT PrettyCompact;


-- ============================================================================
-- 3. Part 증가 추이 비교 / Part Growth Comparison
-- ============================================================================
SELECT
    toStartOfMinute(collected_at) AS minute,
    table_name,
    max(part_count) AS parts,
    max(active_parts) AS active,
    formatReadableSize(max(bytes_on_disk)) AS disk_size,
    max(row_count) AS total_rows
FROM mv_vs_rmv.parts_history
WHERE session_id = '<SESSION_ID>'
GROUP BY minute, table_name
ORDER BY minute, table_name
FORMAT PrettyCompact;


-- ============================================================================
-- 4. Part 증가 추이 - 테이블별 요약 / Part Growth by Table - Summary
-- ============================================================================
SELECT
    table_name,
    min(part_count) AS min_parts,
    max(part_count) AS max_parts,
    avg(part_count) AS avg_parts,
    max(active_parts) AS max_active_parts,
    formatReadableSize(max(bytes_on_disk)) AS max_disk_size,
    max(row_count) AS final_row_count
FROM mv_vs_rmv.parts_history
WHERE session_id = '<SESSION_ID>'
GROUP BY table_name
ORDER BY table_name
FORMAT Vertical;


-- ============================================================================
-- 5. Merge 활동 비교 / Merge Activity Comparison
-- ============================================================================
SELECT
    table_name,
    count() AS merge_count,
    round(sum(merge_duration_ms) / 1000, 2) AS total_merge_sec,
    round(avg(merge_duration_ms), 2) AS avg_merge_ms,
    sum(rows_read) AS total_rows_merged,
    formatReadableSize(sum(bytes_read)) AS total_bytes_merged,
    formatReadableSize(max(memory_usage)) AS peak_merge_memory
FROM mv_vs_rmv.merge_activity
WHERE session_id = '<SESSION_ID>'
GROUP BY table_name
ORDER BY table_name
FORMAT Vertical;


-- ============================================================================
-- 6. 효율성 지표 계산 / Efficiency Metrics Calculation
-- ============================================================================
WITH
mv_stats AS (
    SELECT
        sum(written_rows) AS rows,
        sum(written_bytes) AS bytes,
        sum(query_duration_ms) AS duration,
        sum(query_count) AS queries,
        max(peak_memory_usage_bytes) AS peak_memory
    FROM mv_vs_rmv.resource_metrics
    WHERE session_id = '<SESSION_ID>' AND metric_source = 'MV'
),
rmv_stats AS (
    SELECT
        sum(written_rows) AS rows,
        sum(written_bytes) AS bytes,
        sum(query_duration_ms) AS duration,
        sum(query_count) AS queries,
        max(peak_memory_usage_bytes) AS peak_memory
    FROM mv_vs_rmv.resource_metrics
    WHERE session_id = '<SESSION_ID>' AND metric_source = 'RMV'
)
SELECT
    'MV (Real-time)' AS method,
    mv_stats.queries AS total_queries,
    round(mv_stats.duration / 1000, 2) AS total_duration_sec,
    formatReadableSize(mv_stats.bytes) AS total_bytes_written,
    formatReadableSize(mv_stats.peak_memory) AS peak_memory,
    '' AS separator,
    'RMV (Batch)' AS method2,
    rmv_stats.queries AS total_queries2,
    round(rmv_stats.duration / 1000, 2) AS total_duration_sec2,
    formatReadableSize(rmv_stats.bytes) AS total_bytes_written2,
    formatReadableSize(rmv_stats.peak_memory) AS peak_memory2,
    '' AS separator2,
    'Efficiency Ratio (MV/RMV)' AS ratio_label,
    round(mv_stats.duration / nullIf(rmv_stats.duration, 0), 2) AS duration_ratio,
    round(mv_stats.queries / nullIf(rmv_stats.queries, 0), 2) AS query_ratio,
    round(mv_stats.bytes / nullIf(rmv_stats.bytes, 0), 2) AS bytes_ratio
FROM mv_stats, rmv_stats
FORMAT Vertical;


-- ============================================================================
-- 7. RMV Refresh 활동 분석 / RMV Refresh Activity Analysis
-- ============================================================================
-- Note: 이 쿼리는 시스템 로그 보존 정책에 따라 결과가 다를 수 있습니다
-- This query results may vary based on system log retention policy

SELECT
    event_time,
    event_type,
    duration_ms,
    read_rows,
    written_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(written_bytes) AS written_bytes,
    formatReadableSize(peak_memory_usage) AS peak_memory
FROM system.part_log
WHERE database = 'mv_vs_rmv'
  AND table = 'events_agg_rmv'
  AND event_type = 'MergeParts'
  AND event_time >= (
      SELECT start_time FROM mv_vs_rmv.test_sessions WHERE session_id = '<SESSION_ID>'
  )
ORDER BY event_time
FORMAT PrettyCompact;


-- ============================================================================
-- 8. 데이터 검증 / Data Validation
-- ============================================================================
-- MV와 RMV가 동일한 결과를 생성했는지 검증
-- Verify that MV and RMV produced the same results

SELECT
    'Source' AS table_name,
    count() AS total_rows,
    min(event_time) AS min_time,
    max(event_time) AS max_time
FROM mv_vs_rmv.events_source
UNION ALL
SELECT
    'MV Aggregated' AS table_name,
    count() AS total_rows,
    min(event_time_5min) AS min_time,
    max(event_time_5min) AS max_time
FROM mv_vs_rmv.events_agg_mv
UNION ALL
SELECT
    'RMV Aggregated' AS table_name,
    count() AS total_rows,
    min(event_time_5min) AS min_time,
    max(event_time_5min) AS max_time
FROM mv_vs_rmv.events_agg_rmv
FORMAT Vertical;


-- ============================================================================
-- 9. 시간대별 처리 패턴 비교 / Processing Pattern by Time
-- ============================================================================
-- MV는 지속적, RMV는 5분마다 스파이크 패턴을 보일 것으로 예상
-- Expected: MV shows continuous pattern, RMV shows spike pattern every 5 minutes

SELECT
    toStartOfMinute(collected_at) AS minute,
    metric_source,
    sum(query_count) AS queries,
    round(sum(query_duration_ms) / 1000, 2) AS duration_sec,
    sum(written_rows) AS written_rows
FROM mv_vs_rmv.resource_metrics
WHERE session_id = '<SESSION_ID>'
  AND metric_source IN ('MV', 'RMV')
GROUP BY minute, metric_source
ORDER BY minute, metric_source
FORMAT TabSeparatedWithNames;


-- ============================================================================
-- 10. 최종 요약 리포트 / Final Summary Report
-- ============================================================================
SELECT
    'Test Session' AS section,
    toString(session_id) AS session_id,
    description,
    start_time,
    end_time,
    dateDiff('second', start_time, end_time) AS test_duration_sec
FROM mv_vs_rmv.test_sessions
WHERE session_id = '<SESSION_ID>'
FORMAT Vertical;
