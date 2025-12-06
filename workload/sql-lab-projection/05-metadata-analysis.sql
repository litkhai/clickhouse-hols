-- ============================================
-- ClickHouse Projection Lab - Metadata Analysis
-- 5. 메타데이터 및 스토리지 분석
-- ============================================

-- 테이블 크기 확인
SELECT
    table,
    formatReadableSize(sum(bytes_on_disk)) as table_size,
    sum(rows) as total_rows,
    count() as parts_count
FROM system.parts
WHERE database = 'projection_test' AND active = 1
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC;


-- Projection 크기 확인
SELECT
    parent_name,
    name as projection_name,
    formatReadableSize(sum(bytes_on_disk)) as projection_size,
    sum(rows) as projection_rows,
    count() as parts_count
FROM system.projection_parts
WHERE database = 'projection_test' AND active = 1
GROUP BY parent_name, name
ORDER BY sum(bytes_on_disk) DESC;


-- Projection 목록 확인
SELECT
    database,
    table,
    name as projection_name,
    type,
    sorting_key,
    query
FROM system.projections
WHERE database = 'projection_test';


-- 파티션별 크기 확인
SELECT
    table,
    partition,
    formatReadableSize(sum(bytes_on_disk)) as partition_size,
    sum(rows) as rows_count,
    count() as parts_count
FROM system.parts
WHERE database = 'projection_test' AND active = 1
GROUP BY table, partition
ORDER BY table, partition;


-- 컬럼별 압축 통계
SELECT
    table,
    column,
    type,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed_size,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) as compression_ratio
FROM system.columns
WHERE database = 'projection_test'
GROUP BY table, column, type
ORDER BY sum(data_compressed_bytes) DESC
LIMIT 20;
