-- ============================================
-- JSON 극한 테스트 - Phase 1: 기본 설정
-- 테스트 환경: ClickHouse Cloud 25.10.1.7113
-- 테스트 일시: 2026-01-09
-- ============================================

-- 버전 확인
SELECT version();
-- 결과: 25.10.1.7113

-- 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS json_stress_test;

-- ============================================
-- Test 1-1: max_dynamic_paths=100
-- ============================================
CREATE TABLE json_stress_test.test_paths_100 (
    id UInt64,
    data JSON(max_dynamic_paths=100)
) ENGINE = MergeTree ORDER BY id;

-- 150개 필드 삽입 (100 한계 초과)
INSERT INTO json_stress_test.test_paths_100
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(x), '":', toString(rand() % 1000)),
        range(150),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 결과 확인
SELECT 
    id,
    length(JSONDynamicPaths(data)) as dynamic_path_count,
    length(JSONSharedDataPaths(data)) as shared_path_count
FROM json_stress_test.test_paths_100
LIMIT 10;

/*
결과:
┌─id─┬─dynamic_path_count─┬─shared_path_count─┐
│  0 │                100 │                50 │
│  1 │                100 │                50 │
│  2 │                100 │                50 │
... (모든 행 동일)
└────┴────────────────────┴───────────────────┘
*/

-- ============================================
-- Test 1-2: max_dynamic_paths=1000
-- ============================================
CREATE TABLE json_stress_test.test_paths_1000 (
    id UInt64,
    data JSON(max_dynamic_paths=1000)
) ENGINE = MergeTree ORDER BY id;

-- 2000개 필드 삽입
INSERT INTO json_stress_test.test_paths_1000
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"f_', toString(x), '":', toString(rand() % 1000)),
        range(2000),
        '{'
    ) || '}' as data
FROM numbers(50);

-- 결과 확인
SELECT 
    id,
    length(JSONDynamicPaths(data)) as dynamic_path_count,
    length(JSONSharedDataPaths(data)) as shared_path_count
FROM json_stress_test.test_paths_1000
LIMIT 5;

/*
결과:
┌─id─┬─dynamic_path_count─┬─shared_path_count─┐
│  0 │               1000 │              1000 │
│  1 │               1000 │              1000 │
│  2 │               1000 │              1000 │
│  3 │               1000 │              1000 │
│  4 │               1000 │              1000 │
└────┴────────────────────┴───────────────────┘
*/

-- ============================================
-- Test 1-3: max_dynamic_paths=10000 (문서 권장 최대치)
-- ============================================
CREATE TABLE json_stress_test.test_paths_10000 (
    id UInt64,
    data JSON(max_dynamic_paths=10000)
) ENGINE = MergeTree ORDER BY id;

-- 15000개 필드 삽입
INSERT INTO json_stress_test.test_paths_10000
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"f_', toString(x), '":', toString(rand() % 1000)),
        range(15000),
        '{'
    ) || '}' as data
FROM numbers(10);

-- 결과 확인
SELECT 
    id,
    length(JSONDynamicPaths(data)) as dynamic_path_count,
    length(JSONSharedDataPaths(data)) as shared_path_count,
    dynamic_path_count + shared_path_count as total_paths
FROM json_stress_test.test_paths_10000
LIMIT 5;

/*
결과:
┌─id─┬─dynamic_path_count─┬─shared_path_count─┬─total_paths─┐
│  0 │              10000 │              5000 │       15000 │
│  1 │              10000 │              5000 │       15000 │
│  2 │              10000 │              5000 │       15000 │
│  3 │              10000 │              5000 │       15000 │
│  4 │              10000 │              5000 │       15000 │
└────┴────────────────────┴───────────────────┴─────────────┘
*/

-- ============================================
-- Test 1-4: 50,000개 필드 극한 테스트
-- ============================================
CREATE TABLE json_stress_test.test_paths_extreme (
    id UInt64,
    data JSON(max_dynamic_paths=10000)
) ENGINE = MergeTree ORDER BY id;

-- 50,000개 필드 삽입 (5개 행만)
INSERT INTO json_stress_test.test_paths_extreme
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"f_', toString(x), '":', toString(rand() % 1000)),
        range(50000),
        '{'
    ) || '}' as data
FROM numbers(5);

-- 결과 확인
SELECT 
    id,
    length(JSONDynamicPaths(data)) as dynamic_path_count,
    length(JSONSharedDataPaths(data)) as shared_path_count,
    dynamic_path_count + shared_path_count as total_paths
FROM json_stress_test.test_paths_extreme;

/*
결과:
┌─id─┬─dynamic_path_count─┬─shared_path_count─┬─total_paths─┐
│  0 │              10000 │             40000 │       50000 │
│  1 │              10000 │             40000 │       50000 │
│  2 │              10000 │             40000 │       50000 │
│  3 │              10000 │             40000 │       50000 │
│  4 │              10000 │             40000 │       50000 │
└────┴────────────────────┴───────────────────┴─────────────┘
*/
