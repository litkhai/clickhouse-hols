-- ============================================
-- ClickHouse JSON Type 극한 테스트 - Phase 1 (이전 테스트)
-- 테스트 환경: ClickHouse Cloud 25.10.1.7113
-- 테스트 일시: 2026-01-09
-- ============================================

-- 버전 확인
SELECT version();
-- 결과: 25.10.1.7113

-- ============================================
-- 1. 데이터베이스 생성
-- ============================================
CREATE DATABASE IF NOT EXISTS json_stress_test;

-- ============================================
-- 2. max_dynamic_paths=100 테스트
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
-- 결과: dynamic_path_count=100, shared_path_count=50 (모든 행 동일)

-- ============================================
-- 3. max_dynamic_paths=1000 테스트
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
-- 결과: dynamic_path_count=1000, shared_path_count=1000

-- ============================================
-- 4. max_dynamic_paths=10000 테스트 (문서 권장 최대치)
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
-- 결과: dynamic=10000, shared=5000, total=15000

-- ============================================
-- 5. 극한 테스트: 50,000개 필드
-- ============================================
CREATE TABLE json_stress_test.test_paths_extreme (
    id UInt64,
    data JSON(max_dynamic_paths=10000)
) ENGINE = MergeTree ORDER BY id;

-- 50,000개 필드 삽입 (5개 행)
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
-- 결과: dynamic=10000, shared=40000, total=50000 ✅ 성공!

-- ============================================
-- 6. 고유 필드명 패턴 테스트 (최악의 시나리오)
-- ============================================
CREATE TABLE json_stress_test.test_unique_fields (
    id UInt64,
    data JSON(max_dynamic_paths=1000)
) ENGINE = MergeTree ORDER BY id;

-- 각 행마다 완전히 다른 필드명 사용
INSERT INTO json_stress_test.test_unique_fields
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"row_', toString(number), '_field_', toString(x), '":', toString(rand() % 1000)),
        range(100),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 결과 확인
SELECT 
    id,
    length(JSONDynamicPaths(data)) as dynamic_count,
    length(JSONSharedDataPaths(data)) as shared_count
FROM json_stress_test.test_unique_fields
WHERE id IN (0, 50, 99);
-- 결과:
-- id=0:  dynamic=100, shared=0   (첫 행의 필드가 dynamic으로)
-- id=50: dynamic=0,   shared=100 (이후 행은 모두 shared로)
-- id=99: dynamic=0,   shared=100

-- 전체 고유 경로 수 확인
SELECT 
    uniqExact(path) as total_unique_paths
FROM (
    SELECT arrayJoin(JSONAllPaths(data)) as path
    FROM json_stress_test.test_unique_fields
);
-- 결과: 10,000개 고유 경로

-- ============================================
-- 7. 머지 동작 테스트
-- ============================================
CREATE TABLE json_stress_test.test_merge_behavior (
    id UInt64,
    data JSON(max_dynamic_paths=50)
) ENGINE = MergeTree ORDER BY id;

-- 파트 1: field_0 ~ field_29
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 파트 2: field_20 ~ field_49 (일부 중복)
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    100 + number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(20 + x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 파트 3: field_40 ~ field_69
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    200 + number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(40 + x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 강제 머지
OPTIMIZE TABLE json_stress_test.test_merge_behavior FINAL;

-- 머지 후 상태 확인
SELECT 
    _part,
    count() as rows,
    uniqExact(arrayJoin(JSONDynamicPaths(data))) as unique_dynamic_paths,
    uniqExact(arrayJoin(JSONSharedDataPaths(data))) as unique_shared_paths
FROM json_stress_test.test_merge_behavior
GROUP BY _part;
-- 결과: dynamic=40, shared=20 (70개 중 50개 한계로 인해 재배치)

-- 어떤 필드가 dynamic/shared로 분류되었는지
SELECT 
    'dynamic' as type,
    arraySort(groupArrayDistinct(arrayJoin(JSONDynamicPaths(data)))) as paths
FROM json_stress_test.test_merge_behavior
UNION ALL
SELECT 
    'shared' as type,
    arraySort(groupArrayDistinct(arrayJoin(JSONSharedDataPaths(data)))) as paths
FROM json_stress_test.test_merge_behavior;
-- 결과: 가장 많이 사용된 필드(field_20~49)가 dynamic으로 유지됨

-- ============================================
-- 8. max_dynamic_types 테스트
-- ============================================
CREATE TABLE json_stress_test.test_dynamic_types (
    id UInt64,
    data JSON(max_dynamic_paths=10, max_dynamic_types=5)
) ENGINE = MergeTree ORDER BY id;

-- 다양한 타입 삽입
INSERT INTO json_stress_test.test_dynamic_types VALUES
(1, '{"field": 42}'),
(2, '{"field": 3.14}'),
(3, '{"field": "hello"}'),
(4, '{"field": true}'),
(5, '{"field": [1,2,3]}'),
(6, '{"field": {"nested": 1}}'),
(7, '{"field": "2020-01-01"}'),
(8, '{"field": 12345678901234567890}'),
(9, '{"field": null}'),
(10, '{"field": -999}');

-- 타입 확인
SELECT 
    id,
    data.field as value,
    dynamicType(data.field) as actual_type
FROM json_stress_test.test_dynamic_types
ORDER BY id;
-- 결과: Int64, Float64, String, Bool, Array(Nullable(Int64)) 등 5개 타입

SELECT distinctDynamicTypes(data.field) as types_in_field
FROM json_stress_test.test_dynamic_types;
-- 결과: ['Array(Nullable(Int64))', 'Bool', 'Float64', 'Int64', 'String']

-- ============================================
-- 9. 성능 비교용 테이블
-- ============================================
CREATE TABLE json_stress_test.test_perf_comparison (
    id UInt64,
    data JSON(max_dynamic_paths=5000)
) ENGINE = MergeTree ORDER BY id;

-- 10000개 필드, 100행 삽입
INSERT INTO json_stress_test.test_perf_comparison
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"f_', toString(x), '":', toString(rand() % 10000)),
        range(10000),
        '{'
    ) || '}' as data
FROM numbers(100);

-- Dynamic path 읽기 (f_0 ~ f_4999)
SELECT 
    count(),
    avg(data.f_0::Int64),
    avg(data.f_1000::Int64),
    avg(data.f_4999::Int64)
FROM json_stress_test.test_perf_comparison;
-- 결과: 27ms

-- Shared path 읽기 (f_5000 ~ f_9999)
SELECT 
    count(),
    avg(data.f_5000::Int64),
    avg(data.f_7500::Int64),
    avg(data.f_9999::Int64)
FROM json_stress_test.test_perf_comparison;
-- 결과: 44ms (약 60% 느림)

-- ============================================
-- 10. 테이블 크기 요약
-- ============================================
SELECT 
    table,
    formatReadableSize(sum(bytes_on_disk)) as disk_size,
    sum(rows) as total_rows,
    count() as parts
FROM system.parts
WHERE database = 'json_stress_test' AND active
GROUP BY table
ORDER BY table;

/* 결과:
┌─table──────────────────┬─disk_size──┬─total_rows─┬─parts─┐
│ test_dynamic_types     │ 533.00 B   │ 10         │ 1     │
│ test_merge_behavior    │ 5.68 KiB   │ 300        │ 1     │
│ test_paths_100         │ 5.08 KiB   │ 100        │ 1     │
│ test_paths_1000        │ 13.53 KiB  │ 50         │ 1     │
│ test_paths_10000       │ 89.16 KiB  │ 10         │ 1     │
│ test_paths_extreme     │ 262.69 KiB │ 7          │ 2     │
│ test_perf_comparison   │ 150.43 KiB │ 100        │ 1     │
│ test_unique_fields     │ 35.86 KiB  │ 100        │ 1     │
└────────────────────────┴────────────┴────────────┴───────┘
*/
