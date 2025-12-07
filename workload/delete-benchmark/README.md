# ClickHouse DELETE Mechanism Benchmark Test Guide

[English](#english) | [한국어](#한국어)

---

## English

A comprehensive benchmark test suite comparing three main mechanisms for handling data deletion in ClickHouse.

### 🎯 Purpose

This lab provides practical experience testing and comparing different DELETE mechanisms in ClickHouse:
- **ALTER TABLE DELETE** - Physical deletion
- **ReplacingMergeTree** - Logical deletion with is_deleted flag
- **CollapsingMergeTree** - Logical deletion with sign column

Whether you're optimizing delete operations or choosing the right deletion strategy, this lab offers structured, step-by-step exercises to measure real-world performance characteristics.

### 📁 File Structure

```
delete-benchmark/
├── README.md                      # This file
├── 01_setup_database.sql          # Database and table creation
├── 02_insert_test_data.sql        # Generate 1M rows test data
├── 03_execute_deletes.sql         # Execute 10% data deletion
├── 04_query_performance.sql       # SELECT query performance test
└── 05_generate_report.sql         # Comprehensive report generation
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd workload/delete-benchmark

# Sequential execution
clickhouse-client --queries-file 01_setup_database.sql
clickhouse-client --queries-file 02_insert_test_data.sql
clickhouse-client --queries-file 03_execute_deletes.sql

# Wait for ALTER DELETE mutation to complete (optional)
sleep 30

clickhouse-client --queries-file 04_query_performance.sql
clickhouse-client --queries-file 05_generate_report.sql
```

Or execute all at once:

```bash
for file in 01_setup_database.sql 02_insert_test_data.sql 03_execute_deletes.sql 04_query_performance.sql 05_generate_report.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 Detailed Execution Steps

#### 1. Database Setup

```bash
clickhouse-client --queries-file 01_setup_database.sql
```

**What it does**:
- Creates `delete_test` database
- Creates three test tables:
  - `alter_delete_table`: SharedMergeTree
  - `replacing_merge_table`: SharedReplacingMergeTree
  - `collapsing_merge_table`: SharedCollapsingMergeTree

**Expected time**: < 1 second

---

#### 2. Insert Test Data

```bash
clickhouse-client --queries-file 02_insert_test_data.sql
```

**What it does**:
- Inserts 1,000,000 rows into each table
- Simulates 1 year of event data
- Verifies initial state

**Expected time**: 10-30 seconds (environment dependent)

---

#### 3. Execute DELETE Operations

```bash
clickhouse-client --queries-file 03_execute_deletes.sql
```

**What it does**:
- **ALTER DELETE**: Deletes 100K rows with user_id % 10 = 0 (asynchronous)
- **ReplacingMergeTree**: Marks is_deleted=1 (synchronous)
- **CollapsingMergeTree**: Adds sign=-1 (synchronous)
- Compares before/after states

**Expected time**: 1-5 seconds (ALTER DELETE runs in background)

---

#### 4. Query Performance Test

```bash
clickhouse-client --queries-file 04_query_performance.sql
```

**What it does**:
- Simple COUNT queries
- Event type aggregation queries
- Time-series aggregation queries
- Complex filter + aggregation queries
- Collects performance metrics

**Expected time**: 30 seconds - 2 minutes

---

#### 5. Generate Comprehensive Report

```bash
clickhouse-client --queries-file 05_generate_report.sql
```

**What it does**:
- Table status summary
- Data accuracy comparison
- Query performance summary
- Relative performance comparison
- Storage efficiency comparison
- Final recommendations

**Expected time**: < 5 seconds

### �� Key Checkpoints

#### Check Mutation Status (ALTER DELETE)

```sql
SELECT
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do
FROM system.mutations
WHERE database = 'delete_test'
  AND table = 'alter_delete_table'
ORDER BY create_time DESC;
```

**is_done = 1** means mutation is complete

---

#### Check Real-time Query Performance

```sql
SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory
FROM system.query_log
WHERE event_time >= now() - INTERVAL 5 MINUTE
  AND query LIKE '%delete_test%'
  AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;
```

---

#### Check Storage Usage

```sql
SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table;
```

### 📊 Expected Results

#### Query Performance (Average)

| Method | Aggregation Query | Relative Performance |
|--------|------------------|---------------------|
| ALTER DELETE | ~20-30 ms | 1.0x (baseline) |
| CollapsingMergeTree | ~25-35 ms | 1.2x |
| ReplacingMergeTree FINAL | ~80-120 ms | 3-4x |

#### Storage Usage

| Method | Compressed Size | Relative to Baseline |
|--------|----------------|---------------------|
| ALTER DELETE | ~7 MiB | 1.0x (baseline) |
| CollapsingMergeTree | ~9 MiB | 1.3x |
| ReplacingMergeTree | ~10 MiB | 1.4x |

### 🎨 Customization

#### Change Data Volume

Edit `02_insert_test_data.sql` to change the `numbers()` function value:

```sql
-- 10 million rows instead of 1 million
FROM numbers(10000000)
```

#### Change Delete Ratio

Edit `03_execute_deletes.sql` to change the condition:

```sql
-- Delete 20% instead of 10%
WHERE user_id % 5 = 0  -- (originally user_id % 10 = 0)
```

#### Add Query Patterns

Add your custom queries to `04_query_performance.sql`

### 💡 Performance Tips

#### For ALTER DELETE
- Execute during off-peak hours
- Delete by partition when possible
- Adjust max_alter_threads for parallel processing

#### For ReplacingMergeTree
- Use Materialized Views for pre-aggregation
- Run OPTIMIZE TABLE FINAL periodically
- Avoid FINAL in high-frequency queries

#### For CollapsingMergeTree
- Ensure correct INSERT order (sign=-1 after sign=1)
- Use sum(sign) in all aggregation queries
- Consider VersionedCollapsingMergeTree for order independence

### 🔧 Troubleshooting

#### Mutation Not Completing

```sql
-- Check mutation status
SELECT * FROM system.mutations
WHERE database = 'delete_test' AND NOT is_done;

-- Wait for mutation synchronously
ALTER TABLE delete_test.alter_delete_table
DELETE WHERE user_id % 10 = 0
SETTINGS mutations_sync = 2;  -- Synchronous execution
```

#### Query Performance Not Measured

```sql
-- Verify query_log is enabled
SELECT * FROM system.query_log LIMIT 1;

-- Check log retention settings
SELECT * FROM system.settings
WHERE name LIKE '%query_log%';
```

#### Too Many Parts

```sql
-- Force merge
OPTIMIZE TABLE delete_test.replacing_merge_table FINAL;
OPTIMIZE TABLE delete_test.collapsing_merge_table FINAL;
```

### 🧹 Clean Up

Delete the test database after completion:

```sql
DROP DATABASE IF EXISTS delete_test;
```

### 🛠 Prerequisites

- ClickHouse server (local or cloud)
- ClickHouse client installed
- Basic SQL knowledge
- Sufficient disk space (~100MB)

### 📚 Reference

- [ClickHouse ALTER DELETE Documentation](https://clickhouse.com/docs/en/sql-reference/statements/alter/delete)
- [ReplacingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [CollapsingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree)

### 📝 License

MIT License

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2025-12-01

---

## 한국어

ClickHouse의 데이터 삭제를 처리하는 세 가지 주요 메커니즘을 비교하는 포괄적인 벤치마크 테스트 스위트입니다.

### 🎯 목적

이 랩은 ClickHouse의 다양한 DELETE 메커니즘을 테스트하고 비교하는 실무 경험을 제공합니다:
- **ALTER TABLE DELETE** - 물리적 삭제
- **ReplacingMergeTree** - is_deleted 플래그를 사용한 논리적 삭제
- **CollapsingMergeTree** - sign 컬럼을 사용한 논리적 삭제

삭제 작업을 최적화하거나 올바른 삭제 전략을 선택하려는 경우, 이 랩은 실제 성능 특성을 측정할 수 있는 구조화된 단계별 연습을 제공합니다.

### 📁 파일 구성

```
delete-benchmark/
├── README.md                      # 이 파일
├── 01_setup_database.sql          # 데이터베이스 및 테이블 생성
├── 02_insert_test_data.sql        # 1백만 rows 테스트 데이터 생성
├── 03_execute_deletes.sql         # 10% 데이터 삭제 실행
├── 04_query_performance.sql       # SELECT 쿼리 성능 테스트
└── 05_generate_report.sql         # 종합 리포트 생성
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd workload/delete-benchmark

# 순차 실행
clickhouse-client --queries-file 01_setup_database.sql
clickhouse-client --queries-file 02_insert_test_data.sql
clickhouse-client --queries-file 03_execute_deletes.sql

# ALTER DELETE mutation 완료 대기 (옵션)
sleep 30

clickhouse-client --queries-file 04_query_performance.sql
clickhouse-client --queries-file 05_generate_report.sql
```

또는 한 번에 실행:

```bash
for file in 01_setup_database.sql 02_insert_test_data.sql 03_execute_deletes.sql 04_query_performance.sql 05_generate_report.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 상세 실행 단계

#### 1. 데이터베이스 설정

```bash
clickhouse-client --queries-file 01_setup_database.sql
```

**수행 작업**:
- `delete_test` 데이터베이스 생성
- 세 가지 테스트 테이블 생성:
  - `alter_delete_table`: SharedMergeTree
  - `replacing_merge_table`: SharedReplacingMergeTree
  - `collapsing_merge_table`: SharedCollapsingMergeTree

**예상 시간**: 1초 미만

---

#### 2. 테스트 데이터 삽입

```bash
clickhouse-client --queries-file 02_insert_test_data.sql
```

**수행 작업**:
- 각 테이블에 1,000,000개 rows 삽입
- 1년간의 이벤트 데이터 시뮬레이션
- 초기 상태 확인

**예상 시간**: 10-30초 (환경에 따라 다름)

---

#### 3. DELETE 작업 실행

```bash
clickhouse-client --queries-file 03_execute_deletes.sql
```

**수행 작업**:
- **ALTER DELETE**: user_id % 10 = 0인 100,000 rows 삭제 (비동기)
- **ReplacingMergeTree**: is_deleted=1 마킹 (동기)
- **CollapsingMergeTree**: sign=-1 추가 (동기)
- 삭제 전후 상태 비교

**예상 시간**: 1-5초 (ALTER DELETE는 백그라운드 처리)

---

#### 4. 쿼리 성능 테스트

```bash
clickhouse-client --queries-file 04_query_performance.sql
```

**수행 작업**:
- 단순 COUNT 쿼리
- Event Type별 집계 쿼리
- 시계열 집계 쿼리
- 복잡한 필터 + 집계 쿼리
- 성능 메트릭 수집

**예상 시간**: 30초 - 2분

---

#### 5. 종합 리포트 생성

```bash
clickhouse-client --queries-file 05_generate_report.sql
```

**수행 작업**:
- 테이블 상태 요약
- 데이터 정확성 비교
- 쿼리 성능 요약
- 상대 성능 비교
- 스토리지 효율성 비교
- 최종 권장사항

**예상 시간**: 5초 미만

### 🔍 주요 확인 포인트

#### Mutation 상태 확인 (ALTER DELETE)

```sql
SELECT
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do
FROM system.mutations
WHERE database = 'delete_test'
  AND table = 'alter_delete_table'
ORDER BY create_time DESC;
```

**is_done = 1**이면 mutation 완료

---

#### 실시간 쿼리 성능 확인

```sql
SELECT
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) as read_bytes,
    formatReadableSize(memory_usage) as memory
FROM system.query_log
WHERE event_time >= now() - INTERVAL 5 MINUTE
  AND query LIKE '%delete_test%'
  AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;
```

---

#### 스토리지 사용량 확인

```sql
SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = 'delete_test' AND active
GROUP BY table;
```

### 📊 예상 결과

#### 쿼리 성능 (평균)

| 방법 | 집계 쿼리 | 상대 성능 |
|--------|------------------|---------------------|
| ALTER DELETE | ~20-30 ms | 1.0x (기준) |
| CollapsingMergeTree | ~25-35 ms | 1.2x |
| ReplacingMergeTree FINAL | ~80-120 ms | 3-4x |

#### 스토리지 사용량

| 방법 | 압축 크기 | 기준 대비 |
|--------|----------------|---------------------|
| ALTER DELETE | ~7 MiB | 1.0x (기준) |
| CollapsingMergeTree | ~9 MiB | 1.3x |
| ReplacingMergeTree | ~10 MiB | 1.4x |

### 🎨 커스터마이징

#### 데이터 볼륨 변경

`02_insert_test_data.sql`에서 `numbers()` 함수 값을 변경:

```sql
-- 100만 대신 1000만 rows
FROM numbers(10000000)
```

#### 삭제 비율 변경

`03_execute_deletes.sql`에서 조건 변경:

```sql
-- 10% 대신 20% 삭제
WHERE user_id % 5 = 0  -- (원래는 user_id % 10 = 0)
```

#### 쿼리 패턴 추가

`04_query_performance.sql`에 원하는 쿼리 추가

### 💡 성능 팁

#### ALTER DELETE의 경우
- Off-peak 시간에 실행
- 가능하면 파티션 단위로 삭제
- max_alter_threads로 병렬 처리 조정

#### ReplacingMergeTree의 경우
- Materialized View로 pre-aggregation
- 주기적으로 OPTIMIZE TABLE FINAL 실행
- 고빈도 쿼리에서 FINAL 피하기

#### CollapsingMergeTree의 경우
- 올바른 INSERT 순서 보장 (sign=-1이 sign=1 이후)
- 모든 집계 쿼리에서 sum(sign) 사용
- 순서 독립성을 위해 VersionedCollapsingMergeTree 고려

### 🔧 트러블슈팅

#### Mutation이 완료되지 않음

```sql
-- Mutation 상태 확인
SELECT * FROM system.mutations
WHERE database = 'delete_test' AND NOT is_done;

-- 동기적으로 mutation 대기
ALTER TABLE delete_test.alter_delete_table
DELETE WHERE user_id % 10 = 0
SETTINGS mutations_sync = 2;  -- 동기 실행
```

#### 쿼리 성능 측정이 안됨

```sql
-- query_log 활성화 확인
SELECT * FROM system.query_log LIMIT 1;

-- 로그 보존 기간 확인
SELECT * FROM system.settings
WHERE name LIKE '%query_log%';
```

#### Parts가 너무 많음

```sql
-- 강제 merge
OPTIMIZE TABLE delete_test.replacing_merge_table FINAL;
OPTIMIZE TABLE delete_test.collapsing_merge_table FINAL;
```

### 🧹 정리

테스트 완료 후 데이터베이스 삭제:

```sql
DROP DATABASE IF EXISTS delete_test;
```

### 🛠 사전 요구사항

- ClickHouse 서버 (로컬 또는 클라우드)
- ClickHouse 클라이언트 설치
- 기본 SQL 지식
- 충분한 디스크 공간 (~100MB)

### 📚 참고 자료

- [ClickHouse ALTER DELETE Documentation](https://clickhouse.com/docs/en/sql-reference/statements/alter/delete)
- [ReplacingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [CollapsingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree)

### 📝 라이선스

MIT License

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2025-12-01
