# JSON Type Stress Test

[English](#english) | [한국어](#한국어)

---

## English

A stress test of the `JSON` data type's path limits: what happens as the number of distinct paths per row grows past `max_dynamic_paths`, where the overflow goes, and what reading from that overflow costs.

### 📋 Overview

Every `JSON` column has a budget of *dynamic paths* — paths stored as real subcolumns. Paths beyond `max_dynamic_paths` are not rejected; they spill into shared data, which still queries correctly but far more expensively. This lab pushes a table to 50,000 fields per row, measures the dynamic/shared split at each setting, and times reads on both sides of the boundary.

**Headline result:** reading a shared path was **5.3× slower** and used **3.4× more memory** than reading a dynamic path on the same table.

### 🎯 Key Features

1. **`max_dynamic_paths` sweep** — 100 / 1,000 / 10,000 and an extreme 50,000-field run
2. **Dynamic vs shared path distribution** — `JSONDynamicPaths()` / `JSONSharedDataPaths()`
3. **Worst-case field naming** — a distinct field name on every row
4. **Merge behaviour** — how the path budget is resolved when parts merge
5. **`max_dynamic_types`** — the type-count analogue of the path budget
6. **Read performance across the boundary** — timing, bytes and memory

### 🚀 Quick Start

#### Prerequisites

- ClickHouse 25.10 or newer (the tests were run on ClickHouse Cloud 25.10.1.7113)
- `clickhouse-client`, or the web UI

#### Setup and Run

```bash
cd workload/json-stress-test

clickhouse-client --queries-file 01_setup.sql
clickhouse-client --queries-file 02_unique_merge_test.sql
```

`03_performance_test.sql` is a **recorded result set**, not a runnable script: it holds the measurements from the performance phase as comments. Read it rather than executing it.

### 📚 Test Details

#### Phase 1 — Path Budget (01_setup.sql)

| Test | Setting | Fields per row | Dynamic | Shared |
|------|---------|----------------|---------|--------|
| `test_paths_100` | `max_dynamic_paths=100` | 150 | 100 | 50 |
| `test_paths_1000` | `max_dynamic_paths=1000` | 2,000 | 1,000 | 1,000 |
| `test_paths_10000` | `max_dynamic_paths=10000` | 15,000 | 10,000 | 5,000 |
| `test_paths_extreme` | `max_dynamic_paths=10000` | 50,000 | 10,000 | 40,000 |

Nothing fails. The excess simply moves to shared data — which is exactly why this limit is easy to cross without noticing.

#### Phase 2 — Unique Fields and Merges (02_unique_merge_test.sql)

- **Test 2-1**: a distinct field name on every row, the pathological case for path budgeting
- **Test 2-2**: merge behaviour, i.e. how the dynamic-path set is decided when parts combine
- **Test 2-3**: `max_dynamic_types`, the same budgeting idea applied to type variety

#### Phase 3 — Read Performance (03_performance_test.sql)

Measured on `perf_test_large`, `JSON(max_dynamic_paths=5000)`, 6,100 rows × 5,000 fields, 2.10 MiB on disk:

| Metric | Dynamic path | Shared path | Difference |
|--------|--------------|-------------|------------|
| Query time | 32 ms | 170 ms | **5.3× slower** |
| Memory | 13.36 MiB | 45.57 MiB | **3.4× more** |
| Data read | 405.08 KiB | 248.83 KiB | — |

Note that the shared-path query read *fewer* bytes and was still far slower and heavier: the cost is in reconstructing values from shared data, not in I/O volume.

### 🔑 Key Learning Points

- Exceeding `max_dynamic_paths` is silent — paths spill to shared data instead of erroring
- Shared-path reads cost roughly 5× the time and 3× the memory of dynamic-path reads on the same data
- Fewer bytes read does not mean a cheaper query when values must be reconstructed from shared data
- Frequently queried fields must stay inside the dynamic-path budget; size `max_dynamic_paths` around them, not around the total field count
- `JSONDynamicPaths()` / `JSONSharedDataPaths()` are the tools for checking which side a field landed on
- A distinct field name per row defeats path budgeting entirely — treat unbounded key spaces as a schema problem, not a `JSON`-type setting problem
- 10,000 is the documented practical ceiling for `max_dynamic_paths`; the 50,000-field run stays at 10,000 dynamic and pushes 40,000 to shared

### 📂 File Structure

```
json-stress-test/
├── README.md                   # This document
├── 01_setup.sql                # Phase 1: max_dynamic_paths sweep
├── 02_unique_merge_test.sql    # Phase 2: unique fields, merges, max_dynamic_types
├── 03_performance_test.sql     # Phase 3: recorded performance results (read-only)
├── 01_previous_tests.sql       # Original combined script, superseded by 01–03
└── progress_log.md             # Run log with intermediate measurements
```

### 🔍 Related Labs

- [local/releases/25.11](../../local/releases/25.11/) — Map aggregation, the typed alternative to semi-structured data
- [workload/projection](../projection/) — projections for read patterns a single sort key cannot serve

### 📝 Notes

- Measurements come from ClickHouse Cloud 25.10.1.7113 and will differ on other hardware; the *ratios* are the point
- `01_previous_tests.sql` is kept for provenance — it is the original single-file run that `01`–`03` were split out of, and re-running it recreates the same tables
- `progress_log.md` records an earlier 2,000-field run where query times were similar but memory still differed by 3.75×, which is a useful counterpoint to the headline numbers
- The tables are left in place for inspection; drop the `json_stress_test` database when finished

---

## 한국어

`JSON` 데이터 타입의 경로 한계를 밀어붙이는 스트레스 테스트입니다. 행당 고유 경로 수가 `max_dynamic_paths`를 넘어서면 무슨 일이 일어나는지, 초과분은 어디로 가는지, 그리고 그곳에서 읽는 비용이 얼마인지 측정합니다.

### 📋 개요

모든 `JSON` 컬럼에는 *dynamic path* 예산이 있습니다 — 실제 서브컬럼으로 저장되는 경로입니다. `max_dynamic_paths`를 넘는 경로는 거부되지 않고 shared data로 넘어가며, 조회는 정상적으로 되지만 비용이 훨씬 큽니다. 이 실습은 행당 5만 필드까지 밀어 올리며 설정별 dynamic/shared 분포를 확인하고, 경계 양쪽의 읽기 성능을 측정합니다.

**핵심 결과:** 같은 테이블에서 shared path 읽기는 dynamic path 읽기보다 **5.3배 느리고** 메모리를 **3.4배** 더 썼습니다.

### 🎯 주요 기능

1. **`max_dynamic_paths` 스윕** — 100 / 1,000 / 10,000 및 5만 필드 극한 테스트
2. **dynamic vs shared 경로 분포** — `JSONDynamicPaths()` / `JSONSharedDataPaths()`
3. **최악의 필드명 패턴** — 행마다 완전히 다른 필드명
4. **머지 동작** — 파트 머지 시 경로 예산이 어떻게 결정되는가
5. **`max_dynamic_types`** — 경로 예산의 타입 개수 버전
6. **경계 양쪽의 읽기 성능** — 시간, 바이트, 메모리

### 🚀 빠른 시작

```bash
cd workload/json-stress-test

clickhouse-client --queries-file 01_setup.sql
clickhouse-client --queries-file 02_unique_merge_test.sql
```

`03_performance_test.sql`은 실행 스크립트가 아니라 **측정 결과 기록**입니다(주석 형태). 실행하지 말고 읽어보세요.

### 📚 테스트 상세

#### Phase 1 — 경로 예산 (01_setup.sql)

| 테스트 | 설정 | 행당 필드 | Dynamic | Shared |
|--------|------|-----------|---------|--------|
| `test_paths_100` | `max_dynamic_paths=100` | 150 | 100 | 50 |
| `test_paths_1000` | `max_dynamic_paths=1000` | 2,000 | 1,000 | 1,000 |
| `test_paths_10000` | `max_dynamic_paths=10000` | 15,000 | 10,000 | 5,000 |
| `test_paths_extreme` | `max_dynamic_paths=10000` | 50,000 | 10,000 | 40,000 |

어느 것도 실패하지 않습니다. 초과분은 그냥 shared data로 이동합니다 — 그래서 이 한계를 모르고 넘기기 쉽습니다.

#### Phase 2 — 고유 필드와 머지 (02_unique_merge_test.sql)

- **Test 2-1**: 행마다 다른 필드명 — 경로 예산 관점에서 최악의 시나리오
- **Test 2-2**: 머지 동작 — 파트가 합쳐질 때 dynamic path 집합이 어떻게 정해지는가
- **Test 2-3**: `max_dynamic_types` — 같은 예산 개념을 타입 다양성에 적용

#### Phase 3 — 읽기 성능 (03_performance_test.sql)

`perf_test_large`, `JSON(max_dynamic_paths=5000)`, 6,100행 × 5,000필드, 디스크 2.10 MiB 기준:

| 항목 | Dynamic path | Shared path | 차이 |
|------|--------------|-------------|------|
| 쿼리 시간 | 32 ms | 170 ms | **5.3배 느림** |
| 메모리 | 13.36 MiB | 45.57 MiB | **3.4배 많음** |
| 읽은 데이터 | 405.08 KiB | 248.83 KiB | — |

shared path 쿼리가 바이트를 *더 적게* 읽고도 훨씬 느리고 무거웠다는 점에 주목하세요. 비용은 I/O 양이 아니라 shared data에서 값을 재구성하는 데 있습니다.

### 🔑 핵심 학습 포인트

- `max_dynamic_paths` 초과는 조용히 일어납니다 — 오류가 아니라 shared data로의 이동입니다
- 같은 데이터에서 shared path 읽기는 dynamic path 대비 시간 약 5배, 메모리 약 3배가 듭니다
- 읽은 바이트가 적다고 저렴한 쿼리가 아닙니다 — shared data에서 값을 재구성해야 한다면 더 비쌉니다
- 자주 조회하는 필드는 반드시 dynamic path 예산 안에 있어야 합니다. `max_dynamic_paths`는 전체 필드 수가 아니라 그 필드들을 기준으로 잡으세요
- 어떤 필드가 어느 쪽에 놓였는지는 `JSONDynamicPaths()` / `JSONSharedDataPaths()`로 확인합니다
- 행마다 다른 필드명은 경로 예산 자체를 무력화합니다 — 무한한 키 공간은 `JSON` 타입 설정 문제가 아니라 스키마 설계 문제로 다루세요
- 문서상 실질 상한은 `max_dynamic_paths=10000`입니다. 5만 필드 테스트도 dynamic은 10,000에 머물고 40,000이 shared로 갑니다

### 📂 파일 구조

```
json-stress-test/
├── README.md                   # 이 문서
├── 01_setup.sql                # Phase 1: max_dynamic_paths 스윕
├── 02_unique_merge_test.sql    # Phase 2: 고유 필드, 머지, max_dynamic_types
├── 03_performance_test.sql     # Phase 3: 성능 측정 결과 기록 (읽기 전용)
├── 01_previous_tests.sql       # 01–03으로 분리되기 전의 원본 통합 스크립트
└── progress_log.md             # 중간 측정치가 담긴 진행 로그
```

### 🔍 관련 실습

- [local/releases/25.11](../../local/releases/25.11/) — Map 집계, 준정형 데이터의 타입 지정 대안
- [workload/projection](../projection/) — 단일 정렬 키로 커버되지 않는 읽기 패턴을 위한 프로젝션

### 📝 참고사항

- 측정값은 ClickHouse Cloud 25.10.1.7113 기준이며 하드웨어에 따라 달라집니다 — 중요한 것은 *비율*입니다
- `01_previous_tests.sql`은 이력 보존용입니다. `01`–`03`으로 분리되기 전의 단일 파일이며, 재실행하면 같은 테이블이 다시 생성됩니다
- `progress_log.md`에는 2,000필드로 진행한 이전 실행이 기록돼 있습니다. 그때는 쿼리 시간은 비슷했지만 메모리가 3.75배 차이났는데, 위 대표 수치와 대조해 보면 유용합니다
- 확인을 위해 테이블은 남겨 둡니다. 끝난 뒤 `json_stress_test` 데이터베이스를 삭제하세요

---

**Happy Learning! 🚀**
