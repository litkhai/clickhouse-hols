# MySQL PREWHERE Quick Start

## 빠른 시작 (5분)

### 1. ClickHouse 시작

```bash
docker start clickhouse-test
```

### 2. 테스트 환경 구축

```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/usecase/mysql-prewhere
./00-setup.sh
```

**실행 시간**: ~30초
**생성 데이터**: 1M + 10M rows

### 3. 데모 실행

```bash
./demo-simple.sh
```

**데모 내용**:
- ✅ MySQL 프로토콜로 PREWHERE 쿼리 실행
- ✅ EXPLAIN으로 실행 계획 확인
- ✅ Native 프로토콜과 비교
- ✅ 성능 테스트

## 직접 테스트해보기

### MySQL 클라이언트로 연결

```bash
mysql -h localhost -P 9004 --protocol=TCP -u mysql_user
```

### 예제 쿼리

#### 기본 PREWHERE

```sql
USE default;

SELECT count(*)
FROM prewhere_test
PREWHERE date = '2024-03-01';
```

#### 복잡한 조건

```sql
SELECT category, count(*) as cnt, round(avg(value), 2) as avg_val
FROM prewhere_test
PREWHERE date >= '2024-03-01' AND date < '2024-04-01'
WHERE status = 'active'
GROUP BY category
ORDER BY cnt DESC;
```

#### EXPLAIN으로 확인

```sql
EXPLAIN SYNTAX
SELECT *
FROM prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active';
```

#### 실행 계획 확인

```sql
EXPLAIN PLAN
SELECT *
FROM prewhere_test
PREWHERE date = '2024-03-01'
WHERE status = 'active';
```

## 핵심 포인트

### ✅ PREWHERE는 MySQL 프로토콜에서도 동작

```sql
-- MySQL 클라이언트에서 그대로 사용 가능
SELECT * FROM my_table
PREWHERE indexed_column = 'value'
WHERE other_condition = true;
```

### ✅ 자동 최적화 지원

```sql
SET optimize_move_to_prewhere = 1;  -- 기본값

-- WHERE 조건이 자동으로 최적화됨
SELECT * FROM my_table WHERE date = '2024-01-01';
```

### ✅ 언제 PREWHERE를 사용할까?

1. **인덱스된 컬럼 필터링**
   - ORDER BY에 포함된 컬럼
   - 예: date, user_id

2. **높은 선택도**
   - 전체 데이터의 작은 부분만 선택
   - 예: 특정 날짜, 특정 ID 범위

3. **긴 텍스트 컬럼이 있는 테이블**
   - PREWHERE로 먼저 필터링
   - 불필요한 텍스트 읽기 방지

## 성능 비교 예시

### 10M 행 테이블 테스트

```sql
-- Without PREWHERE
SET optimize_move_to_prewhere = 0;
SELECT count(*), avg(value)
FROM prewhere_test_large
WHERE date = '2024-06-15';
-- Result: 27,397 rows

-- With PREWHERE
SELECT count(*), avg(value)
FROM prewhere_test_large
PREWHERE date = '2024-06-15';
-- Result: 27,397 rows (동일한 결과, 더 빠른 성능)
```

### 고선택도 필터

```sql
SELECT count(*)
FROM prewhere_test_large
PREWHERE date = '2024-06-15' AND user_id < 100
WHERE status = 'active';
-- Result: 27 rows (매우 효율적)
```

## 문제 해결

### MySQL 연결 오류

```bash
# 프로토콜 명시 필요
mysql -h localhost -P 9004 --protocol=TCP -u mysql_user
```

### ClickHouse 재시작

```bash
docker restart clickhouse-test
sleep 5
```

### 데이터 재생성

```bash
./00-setup.sh
```

## 다음 단계

### 전체 테스트 실행

```bash
./run-all-tests.sh
```

### 개별 테스트

```bash
./01-test-mysql-protocol.sh  # MySQL 프로토콜 테스트
./03-verify-prewhere.sh       # 기능 검증
./02-performance-comparison.sh # 성능 비교
```

### 테스트 결과 확인

- [README.md](README.md) - 전체 가이드
- [TEST_RESULTS.md](TEST_RESULTS.md) - 상세 테스트 결과

## 정리

```sql
-- 테스트 데이터 삭제
DROP TABLE IF EXISTS default.prewhere_test;
DROP TABLE IF EXISTS default.prewhere_test_large;
```

## 요약

| 항목 | 지원 여부 | 비고 |
|------|-----------|------|
| MySQL 프로토콜 | ✅ | 완벽 지원 |
| PREWHERE 구문 | ✅ | Native와 동일 |
| EXPLAIN SYNTAX | ✅ | 구문 확인 가능 |
| EXPLAIN PLAN | ✅ | 실행 계획 확인 |
| 자동 최적화 | ✅ | optimize_move_to_prewhere |
| 성능 향상 | ✅ | 측정 가능 |

**결론**: MySQL 프로토콜로 연결해도 ClickHouse의 PREWHERE 기능을 완전히 활용할 수 있습니다! 🎉
