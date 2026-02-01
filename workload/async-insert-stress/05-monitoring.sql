-- ============================================================
-- ClickHouse Async Insert - 모니터링 쿼리
-- ============================================================

-- 현재 Async Insert 버퍼 상태 확인
SELECT
    database,
    table,
    format,
    total_bytes,
    length(`entries.query_id`) as pending_queries
FROM system.asynchronous_inserts
WHERE database = 'async_insert_test';

-- INSERT 성공/실패 통계
SELECT
    toStartOfHour(event_time) as hour,
    count() as total_queries,
    countIf(exception_code = 0) as success,
    countIf(exception_code != 0) as failed,
    round(countIf(exception_code != 0) / count() * 100, 2) as fail_rate_pct
FROM system.query_log
WHERE query LIKE '%async_insert_test%'
  AND query_kind = 'Insert'
  AND type = 'QueryFinish'
  AND event_date = today()
GROUP BY hour
ORDER BY hour DESC;

-- Async Insert Log 확인 (실패 건만)
SELECT
    event_time,
    database,
    table,
    rows,
    bytes,
    status,
    exception
FROM system.asynchronous_insert_log
WHERE status != 'Ok'
  AND event_date >= today() - 1
ORDER BY event_time DESC;

-- 파트 생성 현황 확인
SELECT
    table,
    count() as part_count,
    sum(rows) as total_rows,
    sum(bytes_on_disk) as total_bytes,
    round(sum(rows) / count(), 0) as avg_rows_per_part
FROM system.parts
WHERE database = 'async_insert_test'
  AND active = 1
GROUP BY table
ORDER BY table;

-- 파트별 상세 정보
SELECT
    table,
    name as part_name,
    rows,
    bytes_on_disk,
    data_compressed_bytes,
    data_uncompressed_bytes,
    round(data_compressed_bytes / data_uncompressed_bytes * 100, 2) as compression_ratio_pct
FROM system.parts
WHERE database = 'async_insert_test'
  AND active = 1
ORDER BY table, name;

-- Async Insert 관련 설정 확인
SELECT
    name,
    value,
    description
FROM system.settings
WHERE name LIKE '%async_insert%'
ORDER BY name;
