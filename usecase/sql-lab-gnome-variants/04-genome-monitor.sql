-- ================================================
-- 모니터링 쿼리
-- Monitoring Queries
-- ================================================

-- ================================================
-- 최근 쿼리 성능 확인
-- Check Recent Query Performance
-- ================================================
SELECT
    type,
    query_duration_ms,
    query_id,
    query,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    result_rows
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%genome.variants_full%'
  AND event_time >= now() - INTERVAL 1 HOUR
ORDER BY query_duration_ms DESC
LIMIT 10;

-- ================================================
-- Granule 스킵 효율 확인
-- Check Granule Skip Efficiency
-- ================================================
SELECT
    query_id,
    sum(ProfileEvents['SelectedMarks']) AS selected_marks,
    sum(ProfileEvents['SelectedRows']) AS selected_rows,
    formatReadableSize(sum(ProfileEvents['SelectedBytes'])) AS selected_bytes
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%genome.variants_full%'
  AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY query_id
ORDER BY selected_marks DESC
LIMIT 10;
