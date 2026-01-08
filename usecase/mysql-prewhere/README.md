# MySQL Protocol PREWHERE Testing

이 디렉토리는 ClickHouse의 MySQL 프로토콜을 통해 PREWHERE 기능을 테스트하는 스크립트들을 포함합니다.

## 개요

MySQL 클라이언트로 ClickHouse에 연결해도 PREWHERE 구문을 사용할 수 있습니다. MySQL 프로토콜은 단순히 연결 방식일 뿐, SQL 구문 자체는 ClickHouse 엔진이 처리하기 때문입니다.

## 테스트 구성

### 스크립트 파일

1. **00-setup.sh** - 테스트 환경 구축
   - 테스트용 데이터베이스 및 테이블 생성
   - 샘플 데이터 삽입 (1M + 10M rows)
   - 테이블 최적화

2. **demo-simple.sh** - 간단한 데모 (추천) ⭐
   - 기본 PREWHERE 쿼리 데모
   - MySQL vs Native 프로토콜 비교
   - EXPLAIN으로 실행 계획 확인
   - 즉시 실행 가능한 예제

3. **01-test-mysql-protocol.sh** - MySQL 프로토콜 테스트
   - 기본 PREWHERE 구문 테스트
   - EXPLAIN SYNTAX로 PREWHERE 확인
   - 자동 최적화 테스트
   - 복잡한 조건 테스트

4. **02-performance-comparison.sh** - 성능 비교
   - WHERE only vs PREWHERE 성능 비교
   - 자동 최적화 효과 측정
   - 여러 시나리오에서 실행 시간 측정

5. **03-verify-prewhere.sh** - 기능 검증
   - EXPLAIN PLAN에서 PREWHERE 확인
   - 자동 최적화 검증
   - 결과 일관성 확인
   - 데이터 읽기량 비교

6. **run-all-tests.sh** - 전체 테스트 실행
   - 모든 테스트를 순차적으로 실행
   - 각 단계별 결과 확인

## 사전 요구사항

1. ClickHouse가 로컬에서 실행 중이어야 합니다
2. MySQL 프로토콜 포트(기본 9004)가 활성화되어야 합니다
3. 필요한 클라이언트:
   - `clickhouse-client`
   - `mysql` CLI client

## 실행 방법

### 빠른 데모 (추천)

```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/usecase/mysql-prewhere

# ClickHouse 시작 (Docker)
docker start clickhouse-test

# 환경 설정 및 데이터 생성
./00-setup.sh

# 간단한 데모 실행
./demo-simple.sh
```

### 전체 테스트 실행

```bash
./run-all-tests.sh
```

### 개별 테스트 실행

```bash
# 1. 환경 설정
./00-setup.sh

# 2. 간단한 데모
./demo-simple.sh

# 3. MySQL 프로토콜 테스트
./01-test-mysql-protocol.sh

# 4. 검증 테스트
./03-verify-prewhere.sh

# 5. 성능 비교
./02-performance-comparison.sh
```

## 주요 테스트 내용

### 1. PREWHERE 구문 지원 확인

```sql
-- MySQL 클라이언트에서도 이렇게 쿼리 가능
SELECT * FROM my_table
PREWHERE date = '2024-01-01'
WHERE status = 'active';
```

### 2. 자동 최적화 테스트

```sql
SET optimize_move_to_prewhere = 1;  -- 기본값

-- WHERE 조건이 자동으로 PREWHERE로 변환됨
SELECT * FROM my_table
WHERE date = '2024-01-01' AND status = 'active';
```

### 3. 성능 비교

- WHERE only (최적화 없음)
- 명시적 PREWHERE
- 자동 PREWHERE 최적화

각 케이스에서 다음을 측정:
- 실행 시간 (ms)
- 읽은 행 수
- 읽은 데이터 크기
- 메모리 사용량

### 4. EXPLAIN으로 확인

```sql
EXPLAIN SYNTAX
SELECT * FROM my_table
PREWHERE date = '2024-01-01';

EXPLAIN PLAN
SELECT * FROM my_table
PREWHERE date = '2024-01-01';
```

## 검증 항목

1. ✅ PREWHERE 구문이 MySQL 프로토콜에서 작동하는가?
2. ✅ 자동 최적화가 정상 작동하는가?
3. ✅ PREWHERE와 WHERE의 결과가 일치하는가?
4. ✅ 성능 향상이 측정되는가?
5. ✅ system.query_log에서 실행 내역을 확인할 수 있는가?

## 연결 정보

### Native Protocol
```bash
clickhouse-client --host=localhost --port=9000
```

### MySQL Protocol
```bash
mysql -h localhost -P 9004 --protocol=TCP -u mysql_user
```

## 고려사항

### optimize_move_to_prewhere 설정

ClickHouse는 기본적으로 적합한 WHERE 조건을 자동으로 PREWHERE로 변환합니다. 이 설정은 MySQL 프로토콜 연결에서도 동작합니다.

```sql
SET optimize_move_to_prewhere = 1;  -- 활성화 (기본값)
SET optimize_move_to_prewhere = 0;  -- 비활성화
```

### MySQL 클라이언트 호환성

일부 MySQL 클라이언트나 ORM이 쿼리를 재작성하는 경우가 있으니, 실제 실행되는 쿼리를 `system.query_log`에서 확인하는 것이 좋습니다.

### 쿼리 실행 확인

```sql
SELECT
    event_time,
    query_duration_ms,
    read_rows,
    substring(query, 1, 100) as query_snippet
FROM system.query_log
WHERE query LIKE '%prewhere_test%'
    AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;
```

## 정리

테스트 완료 후 테스트 데이터를 삭제하려면:

```sql
DROP TABLE IF EXISTS default.prewhere_test;
DROP TABLE IF EXISTS default.prewhere_test_large;
```

## 예상 결과

- PREWHERE 사용 시 데이터 읽기량 감소 (30-70%)
- 쿼리 실행 시간 단축 (20-50%)
- 인덱스된 컬럼에서 더 큰 성능 향상

## 문제 해결

### MySQL 프로토콜 연결 실패
```bash
# ClickHouse 설정 확인
cat /etc/clickhouse-server/config.xml | grep mysql_port
```

### PREWHERE 구문 오류
- ClickHouse 버전 확인 (PREWHERE는 오래된 기능으로 대부분의 버전에서 지원)
- EXPLAIN SYNTAX로 구문 변환 확인

### 성능 차이가 없는 경우
- 테이블 크기가 충분히 큰지 확인
- 캐시 워밍업 확인
- 필터링 조건의 선택도(selectivity) 확인
