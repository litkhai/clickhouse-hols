# ClickHouse JSON 극한 테스트 - 진행 로그

## 테스트 환경
- ClickHouse Cloud 25.10.1.7113
- 시작: 2026-01-09

---

## Phase 1 완료 ✅

### 결과 요약
| 테스트 | 필드 수 | Dynamic | Shared | 상태 |
|--------|--------|---------|--------|------|
| test_paths_100 | 150 | 100 | 50 | ✅ |
| test_paths_1000 | 2,000 | 1,000 | 1,000 | ✅ |
| test_paths_10000 | 15,000 | 10,000 | 5,000 | ✅ |
| test_paths_extreme | 50,000 | 10,000 | 40,000 | ✅ |

---

## Phase 2: 성능 테스트 (진행 중)

### Step 2.1: 대용량 테이블 생성 ✅
```sql
CREATE TABLE IF NOT EXISTS json_stress_test.perf_large (
    id UInt64,
    data JSON(max_dynamic_paths=1000)
) ENGINE = MergeTree ORDER BY id
```

### Step 2.2: 첫 번째 데이터 삽입 (2000필드 x 1000행) ✅
```sql
INSERT INTO json_stress_test.perf_large
SELECT 
    number as id,
    arrayFold(
        (acc, x) -> concat(acc, if(acc = '{', '', ','), '"f_', toString(x), '":', toString(rand() % 10000)),
        range(2000),
        '{'
    ) || '}' as data
FROM numbers(1000)
```
결과: 1000행 삽입 완료

### Step 2.3: Dynamic/Shared 분포 확인 ✅
```sql
SELECT 
    length(JSONDynamicPaths(data)) as dynamic_count,
    length(JSONSharedDataPaths(data)) as shared_count
FROM json_stress_test.perf_large LIMIT 1
```
결과: dynamic=1000, shared=1000 (2000필드 중 반반)

### Step 2.4: 성능 비교 테스트 ✅

#### Dynamic path 읽기 (f_0 ~ f_999)
```sql
SELECT count(), sum(data.f_0::Int64), sum(data.f_500::Int64), sum(data.f_999::Int64)
FROM json_stress_test.perf_large
```
- **실행 시간: 13ms**
- 읽은 데이터: 49.80 KiB
- 메모리: 5.98 MiB

#### Shared path 읽기 (f_1000 ~ f_1999)
```sql
SELECT count(), sum(data.f_1000::Int64), sum(data.f_1500::Int64), sum(data.f_1999::Int64)
FROM json_stress_test.perf_large
```
- **실행 시간: 39ms** (약 3배 느림!)
- 읽은 데이터: 49.80 KiB
- 메모리: 18.03 MiB (3배 더 사용)

⚠️ **중요 발견**: Shared path는 Dynamic path보다 3배 느리고 메모리를 3배 더 사용!

### Step 2.5: 데이터 추가 삽입 ✅
```sql
INSERT INTO json_stress_test.perf_large
SELECT 1000 + number as id, ... FROM numbers(5000)
```
결과: 5000행 추가 (타임아웃 발생했으나 삽입됨)
현재 총 행 수: 6000

### Step 2.6: 6000행 성능 테스트 ✅

| 테스트 | 실행시간 | 메모리 | 비고 |
|-------|---------|--------|------|
| Dynamic (f_0, f_999) | 96ms | 7.11 MiB | 기준 |
| Shared (f_1000, f_1999) | 85ms | 26.68 MiB | 메모리 3.75배 |

주: 실행시간은 비슷하지만 메모리 사용량이 크게 다름


