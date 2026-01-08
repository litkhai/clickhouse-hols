-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 5. 모니터링 및 쿼리 분석
-- ============================================

-- ----------------------------------------------------------------------------
-- Query Log 분석
-- ----------------------------------------------------------------------------

-- 최근 쿼리 성능 확인
SELECT
    tables[1] as table_name,
    query_duration_ms,
    read_rows,
    read_bytes,
    formatReadableSize(read_bytes) as read_size,
    result_rows,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%player_g%'
  AND query LIKE '%player_id = 500000%'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 20;


-- Granularity별 평균 성능 비교
SELECT
    tables[1] as table_name,
    count() as query_count,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(avg(read_rows), 0) as avg_read_rows,
    formatReadableSize(avg(read_bytes)) as avg_read_size
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%player_g%'
  AND query LIKE '%WHERE player_id =%'
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY table_name
ORDER BY avg_duration_ms;


-- ----------------------------------------------------------------------------
-- Projection 활용 모니터링
-- ----------------------------------------------------------------------------

-- Projection이 사용된 쿼리 확인
SELECT
    query_id,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_size,
    substring(query, 1, 200) as query_preview
FROM system.query_log
WHERE type = 'QueryFinish'
  AND has(projections, 'user_lookup')
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 20;


-- Projection 사용률 분석
SELECT
    database,
    table,
    arrayJoin(projections) as projection_name,
    count() as usage_count,
    round(avg(query_duration_ms), 2) as avg_duration_ms,
    round(avg(read_rows), 0) as avg_read_rows
FROM system.query_log
WHERE type = 'QueryFinish'
  AND length(projections) > 0
  AND event_time >= now() - INTERVAL 24 HOUR
GROUP BY database, table, projection_name
ORDER BY usage_count DESC;


-- ----------------------------------------------------------------------------
-- Parts 및 Merges 모니터링
-- ----------------------------------------------------------------------------

-- 활성 Merge 작업 확인
SELECT
    database,
    table,
    elapsed,
    progress,
    num_parts,
    formatReadableSize(total_size_bytes_compressed) as size,
    formatReadableSize(bytes_read_uncompressed) as bytes_read,
    formatReadableSize(bytes_written_uncompressed) as bytes_written
FROM system.merges
WHERE database = 'projection_granularity_test'
ORDER BY elapsed DESC;


-- Parts 최적화 상태
SELECT
    database,
    table,
    count() as part_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    min(min_date) as earliest_data,
    max(max_date) as latest_data
FROM system.parts
WHERE database = 'projection_granularity_test'
  AND active = 1
GROUP BY database, table
ORDER BY part_count DESC;
