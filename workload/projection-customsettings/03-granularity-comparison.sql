-- ============================================
-- ClickHouse Projection Custom Settings Lab
-- 3. 기존 Granularity 테스트 데이터 활용
-- ============================================

-- 사용 가능한 데이터베이스 확인
SELECT name FROM system.databases ORDER BY name;

-- granularity_test 데이터베이스의 테이블 확인
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) as size
FROM system.tables
WHERE database = 'granularity_test'
ORDER BY name;


-- ----------------------------------------------------------------------------
-- Point Query 성능 테스트
-- ----------------------------------------------------------------------------

-- G=256 테스트
SELECT
    'G=256' as test,
    count() as found
FROM granularity_test.player_g256
WHERE player_id = 500000;

-- G=1024 테스트
SELECT
    'G=1024' as test,
    count() as found
FROM granularity_test.player_g1024
WHERE player_id = 500000;

-- G=4096 테스트
SELECT
    'G=4096' as test,
    count() as found
FROM granularity_test.player_g4096
WHERE player_id = 500000;

-- G=8192 테스트
SELECT
    'G=8192' as test,
    count() as found
FROM granularity_test.player_g8192
WHERE player_id = 500000;


-- ----------------------------------------------------------------------------
-- 스토리지 및 인덱스 분석
-- ----------------------------------------------------------------------------

-- system.parts를 사용한 상세 분석
SELECT
    table,
    sum(marks) as total_marks,
    formatReadableSize(sum(bytes_on_disk)) as total_size,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) as index_memory,
    round(sum(primary_key_bytes_in_memory_allocated) / sum(bytes_on_disk) * 100, 3) as index_overhead_pct,
    sum(rows) as total_rows
FROM system.parts
WHERE database = 'granularity_test'
  AND table IN ('player_g256', 'player_g1024', 'player_g4096', 'player_g8192')
  AND active = 1
GROUP BY table
ORDER BY total_marks DESC;

/* 예상 결과:
┌─table────────┬─total_marks─┬─total_size─┬─index_memory─┬─index_overhead_pct─┬─total_rows─┐
│ player_g256  │        7814 │ 66.34 MiB  │ 61.17 KiB    │              0.09  │    2000000 │
│ player_g1024 │        1954 │ 57.25 MiB  │ 0.00 B       │              0.0   │    2000000 │
│ player_g4096 │         489 │ 54.34 MiB  │ 0.00 B       │              0.0   │    2000000 │
│ player_g8192 │         245 │ 54.02 MiB  │ 2.04 KiB     │              0.004 │    2000000 │
└──────────────┴─────────────┴────────────┴──────────────┴────────────────────┴────────────┘
*/


-- Granule당 평균 행 수 계산
SELECT
    table,
    sum(rows) as total_rows,
    sum(marks) as total_marks,
    round(sum(rows) / sum(marks), 2) as avg_rows_per_granule,
    CASE
        WHEN table = 'player_g256' THEN 256
        WHEN table = 'player_g1024' THEN 1024
        WHEN table = 'player_g4096' THEN 4096
        WHEN table = 'player_g8192' THEN 8192
    END as configured_granularity,
    round(sum(rows) / sum(marks), 2) /
    CASE
        WHEN table = 'player_g256' THEN 256
        WHEN table = 'player_g1024' THEN 1024
        WHEN table = 'player_g4096' THEN 4096
        WHEN table = 'player_g8192' THEN 8192
    END as efficiency_ratio
FROM system.parts
WHERE database = 'granularity_test'
  AND table IN ('player_g256', 'player_g1024', 'player_g4096', 'player_g8192')
  AND active = 1
GROUP BY table
ORDER BY total_marks DESC;


-- 테이블별 파트 정보 상세
SELECT
    table,
    name as part_name,
    rows,
    marks,
    formatReadableSize(bytes_on_disk) as size,
    formatReadableSize(primary_key_bytes_in_memory_allocated) as pk_memory,
    modification_time
FROM system.parts
WHERE database = 'granularity_test'
  AND table = 'player_g256'
  AND active = 1
ORDER BY modification_time DESC
LIMIT 10;
