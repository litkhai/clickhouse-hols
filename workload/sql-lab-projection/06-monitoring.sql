-- ============================================
-- ClickHouse Projection Lab - Monitoring
-- 6. 쿼리 성능 모니터링
-- ============================================

-- 최근 쿼리 성능 확인
SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    result_rows,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE
    query LIKE '%projection_test.sales_events%'
    AND type = 'QueryFinish'
    AND event_time > now() - INTERVAL 10 MINUTE
ORDER BY event_time DESC
LIMIT 10;


-- Projection 사용 여부 확인
SELECT
    query_id,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    ProfileEvents['SelectedProjectionParts'] as projection_parts_used,
    substring(query, 1, 80) as query_preview
FROM system.query_log
WHERE
    database = 'projection_test'
    AND type = 'QueryFinish'
    AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 20;


-- 쿼리 통계 비교 (Projection 사용 vs 미사용)
SELECT
    if(ProfileEvents['SelectedProjectionParts'] > 0, 'With Projection', 'Without Projection') as query_type,
    count() as query_count,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(avg(read_rows), 0) as avg_rows_read,
    formatReadableSize(round(avg(read_bytes), 0)) as avg_bytes_read,
    formatReadableSize(round(avg(memory_usage), 0)) as avg_memory
FROM system.query_log
WHERE
    database = 'projection_test'
    AND type = 'QueryFinish'
    AND event_time > now() - INTERVAL 1 HOUR
    AND query LIKE '%sales_events%'
    AND query NOT LIKE '%system.query_log%'
GROUP BY query_type;


-- 느린 쿼리 분석
SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    ProfileEvents['SelectedProjectionParts'] as projection_parts,
    exception,
    substring(query, 1, 150) as query_preview
FROM system.query_log
WHERE
    database = 'projection_test'
    AND type = 'QueryFinish'
    AND event_time > now() - INTERVAL 1 HOUR
    AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 10;


-- Mutation 진행 상태 확인 (Projection 구체화)
SELECT
    database,
    table,
    mutation_id,
    command,
    create_time,
    parts_to_do,
    is_done,
    latest_failed_part,
    latest_fail_reason
FROM system.mutations
WHERE database = 'projection_test'
ORDER BY create_time DESC
LIMIT 10;
