-- ============================================================================
-- ClickHouse Index Granularity Point Query Benchmark - Metadata Check
-- ClickHouse Index Granularity Point Query 벤치마크 - 메타데이터 확인
-- ============================================================================
-- Created: 2025-12-25
-- 작성일: 2025-12-25
-- Purpose: Analyze table metadata, storage, and index statistics
-- 목적: 테이블 메타데이터, 스토리지 및 인덱스 통계 분석
-- ============================================================================

-- ============================================================================
-- 1. Table Storage Information
-- 1. 테이블 스토리지 정보
-- ============================================================================

SELECT '=== Table Storage Information / 테이블 스토리지 정보 ===' AS info;

SELECT
    name AS table_name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS compressed_size,
    formatReadableSize(total_bytes_uncompressed) AS uncompressed_size,
    total_marks,
    round(total_bytes / total_bytes_uncompressed * 100, 2) AS compression_ratio_pct
FROM system.tables
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY name;

-- ============================================================================
-- 2. Index Granularity Settings
-- 2. Index Granularity 설정
-- ============================================================================

SELECT '=== Index Granularity Settings / Index Granularity 설정 ===' AS info;

SELECT
    name AS table_name,
    extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity_setting
FROM system.tables
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY name;

-- ============================================================================
-- 3. Parts and Marks Statistics
-- 3. Parts 및 Marks 통계
-- ============================================================================

SELECT '=== Parts and Marks Statistics / Parts 및 Marks 통계 ===' AS info;

SELECT
    table AS table_name,
    name AS part_name,
    rows,
    marks,
    formatReadableSize(bytes_on_disk) AS size_on_disk,
    round(rows / marks, 2) AS avg_rows_per_mark
FROM system.parts
WHERE database = 'granularity_test'
  AND table LIKE 'player_g%'
  AND active = 1
ORDER BY table, name;

-- ============================================================================
-- 4. Index File Sizes by Table
-- 4. 테이블별 인덱스 파일 크기
-- ============================================================================

SELECT '=== Index File Sizes by Table / 테이블별 인덱스 파일 크기 ===' AS info;

SELECT
    table AS table_name,
    count() AS active_parts,
    sum(marks) AS total_marks,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS primary_key_size_memory,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) AS primary_key_size_allocated
FROM system.parts
WHERE database = 'granularity_test'
  AND table LIKE 'player_g%'
  AND active = 1
GROUP BY table
ORDER BY table;

-- ============================================================================
-- 5. Granularity Comparison Summary
-- 5. Granularity 비교 요약
-- ============================================================================

SELECT '=== Granularity Comparison Summary / Granularity 비교 요약 ===' AS info;

SELECT
    name AS table_name,
    extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity,
    total_rows,
    total_marks,
    round(total_rows / total_marks, 2) AS actual_rows_per_mark,
    formatReadableSize(total_bytes) AS table_size,
    round(total_bytes / 1024.0 / 1024.0, 2) AS size_mb
FROM system.tables
WHERE database = 'granularity_test'
  AND name LIKE 'player_g%'
ORDER BY
    CAST(extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS UInt32);

-- ============================================================================
-- 6. Column Statistics
-- 6. 컬럼 통계
-- ============================================================================

SELECT '=== Column Statistics (player_g8192 sample) / 컬럼 통계 (player_g8192 샘플) ===' AS info;

SELECT
    table AS table_name,
    column AS column_name,
    type AS data_type,
    formatReadableSize(data_compressed_bytes) AS compressed_size,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed_size,
    round(data_compressed_bytes / data_uncompressed_bytes * 100, 2) AS compression_pct
FROM system.parts_columns
WHERE database = 'granularity_test'
  AND table = 'player_g8192'
  AND active = 1
GROUP BY table, column, type, data_compressed_bytes, data_uncompressed_bytes
ORDER BY data_compressed_bytes DESC
LIMIT 10;

SELECT '✓ Metadata check completed / 메타데이터 확인 완료';
