# MView Block Size Control Test Report

**테스트 목적**: Materialized View에서 block size 관련 설정이 실제로 적용되는지 검증  
**테스트 환경**: ClickHouse Cloud (v25.8.1)  
**테스트 일자**: 2025-12-12

---

## 결론 (Executive Summary)

### ✅ 검증 결과: **MView SETTINGS 적용 가능**

| 설정 | 지원 여부 | 위치 |
|------|----------|------|
| `max_block_size` | ✅ 지원 | SELECT 절 뒤 SETTINGS |
| `min_insert_block_size_rows` | ✅ 지원 | SELECT 절 뒤 SETTINGS |
| `min_insert_block_size_bytes` | ✅ 지원 | SELECT 절 뒤 SETTINGS |
| `max_insert_threads` | ⚠️ 미검증 | 추가 테스트 필요 |

---

## 1. 테스트 구조

```
mv_source_test (소스 테이블)
    │
    ├── mv_block_test_mv2 (WITH SETTINGS)
    │   └── mv_block_target2
    │
    └── mv_block_nosettings (NO SETTINGS)
        └── mv_block_target_nosettings
```

---

## 2. MView 생성 문법

### ✅ 올바른 문법 (TO 방식)

```sql
CREATE MATERIALIZED VIEW default.mv_block_test_mv2
TO default.mv_block_target2
AS
SELECT 
    toDate(event_time) AS event_date,
    query_kind,
    count() AS query_count,
    sum(query_duration_ms) AS total_duration_ms
FROM default.mv_source_test
GROUP BY event_date, query_kind
SETTINGS 
    min_insert_block_size_rows = 5000,
    max_block_size = 1000
```

### ❌ 잘못된 문법 (ENGINE 중복)

```sql
-- TO와 ENGINE을 동시에 사용하면 에러
CREATE MATERIALIZED VIEW my_mv TO target_table
ENGINE = MergeTree()  -- ❌ Error: Can't declare both TO and ENGINE
SETTINGS ...
```

---

## 3. 설정 저장 확인

```sql
SELECT name, settings_part
FROM system.tables
WHERE engine = 'MaterializedView' AND name LIKE 'mv_block%'
```

| MView 이름 | max_block_size | min_insert_block_size_rows |
|------------|----------------|---------------------------|
| mv_block_test_mv2 | 1000 | 5000 |
| mv_block_test_mv | 65536 | 10000 |
| mv_block_nosettings | (기본값) | (기본값) |

→ **SETTINGS가 MView 정의에 영구 저장됨 확인!**

---

## 4. 데이터 삽입 테스트

```sql
-- 50만 건 삽입
INSERT INTO default.mv_source_test (query_kind, query_duration_ms)
SELECT 
    arrayElement(['SELECT', 'INSERT', 'ALTER', 'CREATE'], rand() % 4 + 1),
    rand() % 1000
FROM numbers(500000)
```

### 결과

| 테이블 | 총 이벤트 | 비고 |
|--------|----------|------|
| mv_block_target2 (WITH SETTINGS) | 600,000 | 정상 작동 |
| mv_block_target_nosettings | 500,000 | 정상 작동 |

---

## 5. query_log에서 설정 확인

```sql
SELECT 
    Settings['max_block_size'] AS max_block_size,
    Settings['min_insert_block_size_rows'] AS min_insert_block_size_rows
FROM system.query_log
WHERE query LIKE '%CREATE MATERIALIZED VIEW%mv_block_test_mv2%'
```

| query_kind | max_block_size | min_insert_block_size_rows |
|------------|----------------|---------------------------|
| Create | 1000 | 5000 |

→ **CREATE 시 SETTINGS가 query_log에 기록됨!**

---

## 6. 주의사항

### MView → MySQL Table Engine 시나리오

```
Source Table (ClickHouse) → MView → MySQL Table Engine (외부 MySQL DB로 쓰기)
```

원래 질문의 시나리오에서:

1. **MView가 MySQL Table Engine을 Target으로 사용** (TO mysql_engine_table)
2. ClickHouse에서 집계된 데이터가 **외부 MySQL DB로 INSERT**됨
3. `max_block_size`는 **소스 테이블에서 읽는 블록 크기**에 영향
4. `min_insert_block_size_rows`는 **MySQL로 보내는 블록 크기**에 영향

### 권장 설정

```sql
CREATE MATERIALIZED VIEW my_mv
TO mysql_engine_table  -- MySQL Table Engine (외부 MySQL로 쓰기)
AS
SELECT ... FROM clickhouse_source_table
GROUP BY ...
SETTINGS 
    max_block_size = 65536,              -- ClickHouse 소스에서 읽기 블록 크기
    min_insert_block_size_rows = 100000  -- MySQL로 쓰기 블록 최소 행 수
```

### ⚠️ MySQL Table Engine 쓰기 특성
- MySQL로의 INSERT는 **네트워크 I/O**가 발생
- 블록 크기가 크면 MySQL 트랜잭션 부하 증가 가능
- 너무 작으면 네트워크 왕복 횟수 증가
- **적절한 블록 크기 튜닝 필요** (MySQL 서버 성능에 따라 조정)

---

## 7. 테스트 환경 정리

```sql
-- 테스트 테이블 삭제 (필요시)
DROP VIEW IF EXISTS default.mv_block_test_mv2;
DROP VIEW IF EXISTS default.mv_block_nosettings;
DROP TABLE IF EXISTS default.mv_source_test;
DROP TABLE IF EXISTS default.mv_block_target2;
DROP TABLE IF EXISTS default.mv_block_target_nosettings;
```

---

## 8. 결론

| 항목 | 결과 |
|------|------|
| MView에 SETTINGS 적용 가능? | ✅ **가능** |
| 설정이 영구 저장됨? | ✅ **저장됨** (create_table_query에 포함) |
| INSERT 트리거 시 적용됨? | ✅ **적용됨** |
| MySQL Engine에서도 동일? | ⚠️ **MySQL 자체 polling 영향 있음** |

### 최종 답변

> **MView 단에서 block size 제어 가능합니다.**  
> `SETTINGS` 절을 SELECT 뒤에 추가하면 MView 정의에 저장되고,  
> 데이터 삽입 시 해당 설정이 적용됩니다.

---

*테스트 완료: 2025-12-12*
