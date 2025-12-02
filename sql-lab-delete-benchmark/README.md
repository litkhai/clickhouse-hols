# ClickHouse DELETE Mechanism Benchmark Test Guide
# ClickHouse DELETE 메커니즘 벤치마크 테스트 가이드

## Overview / 개요

This directory contains benchmark test scripts comparing three main mechanisms for handling data deletion in ClickHouse.

이 디렉토리는 ClickHouse에서 데이터 삭제를 처리하는 세 가지 주요 메커니즘의 성능을 비교하는 벤치마크 테스트 스크립트를 포함합니다.

**Test Targets / 테스트 대상**:
- ALTER TABLE DELETE (Physical deletion / 물리적 삭제)
- ReplacingMergeTree with is_deleted flag (Logical deletion / 논리적 삭제)
- CollapsingMergeTree with sign column (Logical deletion / 논리적 삭제)

## File Structure / 파일 구성

```
delete_benchmark/
├── README.md                      # This file / 이 파일
├── 01_setup_database.sql          # Database and table creation / 데이터베이스 및 테이블 생성
├── 02_insert_test_data.sql        # Generate 1M rows test data / 1백만 rows 테스트 데이터 생성
├── 03_execute_deletes.sql         # Execute 10% data deletion / 10% 데이터 삭제 실행
├── 04_query_performance.sql       # SELECT query performance test / SELECT 쿼리 성능 테스트
└── 05_generate_report.sql         # Comprehensive report generation / 종합 리포트 생성
```

## Execution Order / 실행 순서

### 1. Database Setup / 데이터베이스 설정

```bash
clickhouse-client --queries-file 01_setup_database.sql
```

**What it does / 수행 작업**:
- Creates `delete_test` database / `delete_test` 데이터베이스 생성
- Creates three test tables / 세 가지 테스트 테이블 생성
  - `alter_delete_table`: SharedMergeTree
  - `replacing_merge_table`: SharedReplacingMergeTree
  - `collapsing_merge_table`: SharedCollapsingMergeTree

**Expected time / 예상 시간**: < 1 second / 1초 미만

### 2. Insert Test Data / 테스트 데이터 삽입

```bash
clickhouse-client --queries-file 02_insert_test_data.sql
```

**What it does / 수행 작업**:
- Inserts 1,000,000 rows into each table / 각 테이블에 1,000,000개 rows 삽입
- Simulates 1 year of event data / 1년간의 이벤트 데이터 시뮬레이션
- Verifies initial state / 초기 상태 확인

**Expected time / 예상 시간**: 10-30 seconds (environment dependent / 환경에 따라 다름)

### 3. Execute DELETE Operations / DELETE 작업 실행

```bash
clickhouse-client --queries-file 03_execute_deletes.sql
```

**What it does / 수행 작업**:
- ALTER DELETE: Deletes 100K rows with user_id % 10 = 0 (asynchronous) / 100,000 rows 삭제 (비동기)
- ReplacingMergeTree: Marks is_deleted=1 (synchronous) / is_deleted=1 마킹 (동기)
- CollapsingMergeTree: Adds sign=-1 (synchronous) / sign=-1 추가 (동기)
- Compares before/after states / 삭제 전후 상태 비교

**Expected time / 예상 시간**: 1-5 seconds (ALTER DELETE runs in background / ALTER DELETE는 백그라운드 처리)

### 4. Query Performance Test / 쿼리 성능 테스트

```bash
clickhouse-client --queries-file 04_query_performance.sql
```

**What it does / 수행 작업**:
- Simple COUNT queries / 단순 COUNT 쿼리
- Event type aggregation queries / Event Type별 집계 쿼리
- Time-series aggregation queries / 시계열 집계 쿼리
- Complex filter + aggregation queries / 복잡한 필터 + 집계 쿼리
- Collects performance metrics / 성능 메트릭 수집

**Expected time / 예상 시간**: 30 seconds - 2 minutes / 30초 - 2분

### 5. Generate Comprehensive Report / 종합 리포트 생성

```bash
clickhouse-client --queries-file 05_generate_report.sql
```

**What it does / 수행 작업**:
- Table status summary / 테이블 상태 요약
- Data accuracy comparison / 데이터 정확성 비교
- Query performance summary / 쿼리 성능 요약
- Relative performance comparison / 상대 성능 비교
- Storage efficiency comparison / 스토리지 효율성 비교
- Final recommendations / 최종 권장사항

**Expected time / 예상 시간**: < 5 seconds / 5초 미만

## Complete Execution (All at once) / 전체 실행 (한 번에)

```bash
# Sequential execution / 순차 실행
clickhouse-client --queries-file 01_setup_database.sql
clickhouse-client --queries-file 02_insert_test_data.sql
clickhouse-client --queries-file 03_execute_deletes.sql

# Wait for ALTER DELETE mutation to complete (optional) / ALTER DELETE mutation 완료 대기 (옵션)
sleep 30

clickhouse-client --queries-file 04_query_performance.sql
clickhouse-client --queries-file 05_generate_report.sql
```

Or in a single command / 또는 하나의 명령으로:

```bash
for file in 01_setup_database.sql 02_insert_test_data.sql 03_execute_deletes.sql 04_query_performance.sql 05_generate_report.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

## Key Checkpoints / 주요 확인 포인트

### 1. Check Mutation Status (ALTER DELETE) / Mutation 상태 확인

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

**is_done = 1** means mutation is complete / mutation 완료

### 2. Check Real-time Query Performance / 실시간 쿼리 성능 확인

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

### 3. Check Storage Usage / 스토리지 사용량 확인

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

## Expected Results / 예상 결과

### Query Performance (Average) / 쿼리 성능 (평균)

| Method / 방법 | Aggregation Query / 집계 쿼리 | Relative Performance / 상대 성능 |
|--------|------------------|---------------------|
| ALTER DELETE | ~20-30 ms | 1.0x (baseline / 기준) |
| CollapsingMergeTree | ~25-35 ms | 1.2x |
| ReplacingMergeTree FINAL | ~80-120 ms | 3-4x |

### Storage Usage / 스토리지 사용량

| Method / 방법 | Compressed Size / 압축 크기 | Relative to Baseline / 기준 대비 |
|--------|----------------|---------------------|
| ALTER DELETE | ~7 MiB | 1.0x (baseline / 기준) |
| CollapsingMergeTree | ~9 MiB | 1.3x |
| ReplacingMergeTree | ~10 MiB | 1.4x |

## Customization / 커스터마이징

### Change Data Volume / 데이터 볼륨 변경

Edit `02_insert_test_data.sql` to change the `numbers()` function value:

`02_insert_test_data.sql`에서 `numbers()` 함수 값을 변경:

```sql
-- 10 million rows instead of 1 million / 100만 대신 1000만 rows
FROM numbers(10000000)
```

### Change Delete Ratio / 삭제 비율 변경

Edit `03_execute_deletes.sql` to change the condition:

`03_execute_deletes.sql`에서 조건 변경:

```sql
-- Delete 20% instead of 10% / 10% 대신 20% 삭제
WHERE user_id % 5 = 0  -- (originally user_id % 10 = 0 / 원래는 user_id % 10 = 0)
```

### Add Query Patterns / 쿼리 패턴 추가

Add your custom queries to `04_query_performance.sql`

`04_query_performance.sql`에 원하는 쿼리 추가

## Clean Up / 정리

Delete the test database after completion:

테스트 완료 후 데이터베이스 삭제:

```sql
DROP DATABASE IF EXISTS delete_test;
```

## Troubleshooting / 트러블슈팅

### Mutation Not Completing / Mutation이 완료되지 않음

```sql
-- Check mutation status / Mutation 상태 확인
SELECT * FROM system.mutations 
WHERE database = 'delete_test' AND NOT is_done;

-- Wait for mutation synchronously / 동기적으로 mutation 대기
ALTER TABLE delete_test.alter_delete_table 
DELETE WHERE user_id % 10 = 0
SETTINGS mutations_sync = 2;  -- Synchronous execution / 동기 실행
```

### Query Performance Not Measured / 쿼리 성능 측정이 안됨

```sql
-- Verify query_log is enabled / query_log 활성화 확인
SELECT * FROM system.query_log LIMIT 1;

-- Check log retention settings / 로그 보존 기간 확인
SELECT * FROM system.settings 
WHERE name LIKE '%query_log%';
```

### Too Many Parts / Parts가 너무 많음

```sql
-- Force merge / 강제 merge
OPTIMIZE TABLE delete_test.replacing_merge_table FINAL;
OPTIMIZE TABLE delete_test.collapsing_merge_table FINAL;
```

## Performance Tips / 성능 팁

### For ALTER DELETE / ALTER DELETE의 경우

- Execute during off-peak hours / Off-peak 시간에 실행
- Delete by partition when possible / 가능하면 파티션 단위로 삭제
- Adjust max_alter_threads for parallel processing / max_alter_threads로 병렬 처리 조정

### For ReplacingMergeTree / ReplacingMergeTree의 경우

- Use Materialized Views for pre-aggregation / Materialized View로 pre-aggregation
- Run OPTIMIZE TABLE FINAL periodically / 주기적으로 OPTIMIZE TABLE FINAL 실행
- Avoid FINAL in high-frequency queries / 고빈도 쿼리에서 FINAL 피하기

### For CollapsingMergeTree / CollapsingMergeTree의 경우

- Ensure correct INSERT order (sign=-1 after sign=1) / 올바른 INSERT 순서 보장 (sign=-1이 sign=1 이후)
- Use sum(sign) in all aggregation queries / 모든 집계 쿼리에서 sum(sign) 사용
- Consider VersionedCollapsingMergeTree for order independence / 순서 독립성을 위해 VersionedCollapsingMergeTree 고려

## Reference / 참고 자료

- [ClickHouse ALTER DELETE Documentation](https://clickhouse.com/docs/en/sql-reference/statements/alter/delete)
- [ReplacingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [CollapsingMergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/collapsingmergetree)

## License / 라이선스

MIT License

## Author / 작성자

Ken (ClickHouse Solution Architect)  
Created: 2025-12-01 / 작성일: 2025-12-01
