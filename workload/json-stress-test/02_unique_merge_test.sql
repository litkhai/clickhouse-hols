-- ============================================
-- JSON 극한 테스트 - Phase 2: 고유 필드 및 머지 테스트
-- ============================================

-- ============================================
-- Test 2-1: 각 행마다 다른 필드명 (최악의 시나리오)
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

/*
결과:
┌─id─┬─dynamic_count─┬─shared_count─┐
│  0 │           100 │            0 │  -- 첫 행: 모두 dynamic
│ 50 │             0 │          100 │  -- 이후 행: 모두 shared
│ 99 │             0 │          100 │
└────┴───────────────┴──────────────┘
*/

-- 전체 고유 경로 수 확인
SELECT 
    uniqExact(path) as total_unique_paths
FROM (
    SELECT arrayJoin(JSONAllPaths(data)) as path
    FROM json_stress_test.test_unique_fields
);
-- 결과: 10,000개 (100행 × 100필드)

-- ============================================
-- Test 2-2: 머지 동작 테스트
-- ============================================
CREATE TABLE json_stress_test.test_merge_behavior (
    id UInt64,
    data JSON(max_dynamic_paths=50)
) ENGINE = MergeTree ORDER BY id;

-- 파트 1: field_0 ~ field_29 (30개 필드, 100행)
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 파트 2: field_20 ~ field_49 (30개 필드, 일부 중복, 100행)
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    100 + number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(20 + x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 파트 3: field_40 ~ field_69 (30개 필드, 100행)
INSERT INTO json_stress_test.test_merge_behavior
SELECT 
    200 + number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"field_', toString(40 + x), '":', toString(rand() % 1000)),
        range(30),
        '{'
    ) || '}' as data
FROM numbers(100);

-- 머지 전 파트별 상태 확인
SELECT 
    _part,
    count() as rows,
    arraySort(groupArrayDistinct(arrayJoin(JSONDynamicPaths(data)))) as dynamic_paths_sample
FROM json_stress_test.test_merge_behavior
GROUP BY _part
ORDER BY _part;

-- 강제 머지 실행
OPTIMIZE TABLE json_stress_test.test_merge_behavior FINAL;

-- 머지 후 상태 확인
SELECT 
    _part,
    count() as rows,
    uniqExact(arrayJoin(JSONDynamicPaths(data))) as unique_dynamic_paths,
    uniqExact(arrayJoin(JSONSharedDataPaths(data))) as unique_shared_paths
FROM json_stress_test.test_merge_behavior
GROUP BY _part;

/*
머지 후 결과:
- Dynamic: 50개 (가장 많이 사용된 필드)
- Shared: 20개 (덜 사용된 필드)
*/

-- 어떤 필드가 dynamic/shared로 분류되었는지 확인
SELECT 
    'dynamic' as type,
    arraySort(groupArrayDistinct(arrayJoin(JSONDynamicPaths(data)))) as paths
FROM json_stress_test.test_merge_behavior
UNION ALL
SELECT 
    'shared' as type,
    arraySort(groupArrayDistinct(arrayJoin(JSONSharedDataPaths(data)))) as paths
FROM json_stress_test.test_merge_behavior;

/*
결과:
- Shared: field_54~69, field_6~9 (특정 파트에서만 사용된 필드)
- Dynamic: field_0~53 중 가장 많이 사용된 50개
*/

-- ============================================
-- Test 2-3: max_dynamic_types 테스트
-- ============================================
CREATE TABLE json_stress_test.test_dynamic_types (
    id UInt64,
    data JSON(max_dynamic_paths=10, max_dynamic_types=5)
) ENGINE = MergeTree ORDER BY id;

-- 같은 필드에 다양한 타입의 값 삽입
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

-- Dynamic 타입 내 실제 타입 분포 확인
SELECT 
    id,
    data.field as value,
    dynamicType(data.field) as actual_type
FROM json_stress_test.test_dynamic_types
ORDER BY id;

/*
결과:
┌─id─┬─value────────┬─actual_type────────────┐
│  1 │ 42           │ Int64                  │
│  2 │ 3.14         │ Float64                │
│  3 │ hello        │ String                 │
│  4 │ true         │ Bool                   │
│  5 │ [1,2,3]      │ Array(Nullable(Int64)) │
│  6 │ null         │ None                   │  -- 중첩 객체는 한계 초과
│  7 │ 2020-01-01   │ String                 │
│  8 │ 1.23e19      │ Float64                │
│  9 │ null         │ None                   │
│ 10 │ -999         │ Int64                  │
└────┴──────────────┴────────────────────────┘
*/

-- max_dynamic_types=5 제한 확인
SELECT distinctDynamicTypes(data.field) as types_in_field
FROM json_stress_test.test_dynamic_types;

/*
결과: ['Array(Nullable(Int64))', 'Bool', 'Float64', 'Int64', 'String']
- 정확히 5개 타입
*/
