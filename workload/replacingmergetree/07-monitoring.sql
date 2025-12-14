-- ============================================
-- ReplacingMergeTree Lab - Monitoring
-- 7. 모니터링 쿼리 (운영 환경용)
-- ============================================

-- 파트 상태 모니터링
SELECT
    table,
    count() as part_count,
    sum(rows) as total_rows,
    min(modification_time) as oldest_part,
    dateDiff('hour', min(modification_time), now()) as oldest_age_hours
FROM system.parts
WHERE database = 'blog_test' AND active = 1
GROUP BY table
HAVING part_count > 1
ORDER BY oldest_age_hours DESC;

-- 중복 가능성 체크 (FINAL 유무 행 수 비교)
SELECT
    table,
    count_without_final,
    count_with_final,
    count_without_final - count_with_final as duplicate_rows,
    round((count_without_final - count_with_final) / count_with_final * 100, 2) as duplicate_pct
FROM (
    SELECT
        'user_events_large' as table,
        (SELECT count(*) FROM blog_test.user_events_large) as count_without_final,
        (SELECT count(*) FROM blog_test.user_events_large FINAL) as count_with_final
);

-- 쿼리 성능 비교 (query_log 확인)
SELECT
    query,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    formatReadableSize(memory_usage) as memory
FROM system.query_log
WHERE type = 'QueryFinish'
    AND event_time > now() - INTERVAL 10 MINUTE
    AND query LIKE '%user_events_large%'
    AND query NOT LIKE '%system%'
ORDER BY event_time DESC
LIMIT 20;

-- 테이블별 통계
SELECT
    database,
    table,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    count() as part_count,
    avg(rows) as avg_rows_per_part
FROM system.parts
WHERE database = 'blog_test' AND active = 1
GROUP BY database, table
ORDER BY table;

-- 파트 크기 분포
SELECT
    table,
    rows,
    formatReadableSize(bytes_on_disk) as size,
    formatReadableSize(data_compressed_bytes) as compressed,
    formatReadableSize(data_uncompressed_bytes) as uncompressed,
    round(data_compressed_bytes / data_uncompressed_bytes, 3) as compression_ratio
FROM system.parts
WHERE database = 'blog_test' AND active = 1
ORDER BY table, rows DESC;

-- 최근 merge 활동
SELECT
    event_type,
    event_time,
    table,
    rows,
    size_in_bytes,
    duration_ms,
    error
FROM system.part_log
WHERE database = 'blog_test'
    AND event_time > now() - INTERVAL 1 DAY
    AND event_type IN ('NewPart', 'MergeParts', 'RemovePart')
ORDER BY event_time DESC
LIMIT 50;

-- Background task 상태
SELECT
    metric,
    value
FROM system.metrics
WHERE metric LIKE '%Background%' OR metric LIKE '%Merge%'
ORDER BY metric;

-- 현재 실행 중인 쿼리 (FINAL 포함)
SELECT
    query_id,
    user,
    elapsed,
    read_rows,
    formatReadableSize(memory_usage) as memory,
    query
FROM system.processes
WHERE query LIKE '%FINAL%'
ORDER BY elapsed DESC;
