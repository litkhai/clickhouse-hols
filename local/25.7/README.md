# ClickHouse 25.7 New Features Lab

ClickHouse 25.7 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.7에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

## 📋 Overview

ClickHouse 25.7은 혁신적인 SQL UPDATE/DELETE 최적화, AI 기반 SQL 생성, count() 집계 최적화, JOIN 성능 개선, 그리고 대규모 bulk UPDATE 성능 향상을 포함합니다.

### 🎯 Key Features

1. **SQL UPDATE and DELETE Operations** - 경량 patch-part 메커니즘으로 최대 1000배 빠른 업데이트/삭제
2. **AI-Powered SQL Generation** - OpenAI/Anthropic API를 이용한 자연어 SQL 생성 (??  prefix)
3. **count() Aggregation Optimization** - 20-30% 빠른 집계 성능과 메모리 사용량 감소
4. **JOIN Performance Improvements** - 최대 1.8배 빠른 JOIN 연산
5. **Bulk UPDATE Performance** - PostgreSQL 대비 최대 4000배 빠른 대량 업데이트

## 🚀 Quick Start

### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성

### Setup and Run

```bash
# 1. ClickHouse 25.7 설치 및 시작
cd local/25.7
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-sql-update-delete.sh
./02-count-optimization.sh
./03-join-performance.sh
./04-bulk-update.sh
```

### Manual Execution (SQL only)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2507

# SQL 파일 실행
cd ../25.7
source 01-sql-update-delete.sql
```

## 📚 Feature Details

### 1. SQL UPDATE and DELETE Operations (01-sql-update-delete)

**새로운 기능:** 경량 patch-part 메커니즘을 사용한 UPDATE/DELETE (최대 1000배 빠름)

**테스트 내용:**
- 단일 레코드 UPDATE 성능
- 조건부 대량 UPDATE (WHERE 절)
- 복잡한 표현식을 이용한 UPDATE
- 경량 DELETE 연산 (최대 1000배 빠름)
- 재고 관리 시스템 실습
- 1000만 행 대규모 테이블 업데이트

**실행:**
```bash
./01-sql-update-delete.sh
# 또는
cat 01-sql-update-delete.sql | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- Patch-part 메커니즘: 전체 파트를 다시 쓰지 않고 변경 사항만 저장
- ALTER TABLE UPDATE 구문으로 최적화된 업데이트
- WHERE 조건을 이용한 선택적 업데이트
- CASE 문을 이용한 조건부 값 설정
- 서브쿼리를 이용한 복잡한 업데이트 로직
- 비동기 실행으로 시스템 리소스 효율성

**실무 활용:**
- 실시간 재고 관리 및 가격 조정
- E-커머스 프로모션 및 할인 적용
- 데이터 품질 개선 및 정정 작업
- 사용자 프로필 및 설정 업데이트
- 배치 데이터 처리 및 ETL 파이프라인
- GDPR 준수를 위한 데이터 삭제

**성능 비교:**
- 전통적인 방식: 전체 파트 재작성 필요 (느림)
- ClickHouse 25.7: Patch-part로 변경 사항만 적용 (최대 1000배 빠름)

---

### 2. count() Aggregation Optimization (02-count-optimization)

**새로운 기능:** 최적화된 count() 집계 함수 (20-30% 빠르고 메모리 사용량 감소)

**테스트 내용:**
- 기본 count() 성능 측정
- GROUP BY와 함께 사용되는 count() 최적화
- count(DISTINCT) 성능 개선
- 대규모 데이터셋 (1000만 행) 집계
- 다차원 집계 시나리오
- 메모리 효율성 테스트

**실행:**
```bash
./02-count-optimization.sh
```

**주요 학습 포인트:**
- count()가 가장 빠른 집계 함수 (메타데이터 활용)
- count(column)보다 count()가 더 효율적
- GROUP BY와 함께 사용 시 20-30% 성능 향상
- count(DISTINCT)의 메모리 최적화
- countIf()를 이용한 조건부 집계
- 윈도우 함수와 함께 사용하는 count()

**실무 활용:**
- 실시간 분석 대시보드
- 대규모 이벤트 추적 및 사용자 행동 분석
- 다차원 비즈니스 인텔리전스 리포팅
- 로그 집계 및 모니터링 시스템
- E-커머스 전환율 분석
- IoT 데이터 처리 및 디바이스 텔레메트리

**최적화 팁:**
- 가능하면 count() 사용 (count(column) 대신)
- 적절한 인덱스와 ORDER BY 키 설정
- 파티션을 이용한 쿼리 범위 제한
- Materialized View로 사전 집계

---

### 3. JOIN Performance Improvements (03-join-performance)

**새로운 기능:** 최대 1.8배 빠른 JOIN 연산 성능

**테스트 내용:**
- INNER JOIN 성능 (최대 1.8배 빠름)
- LEFT JOIN 최적화
- 다중 테이블 JOIN (3개 이상)
- JOIN과 GROUP BY 조합
- 복잡한 분석 쿼리 (서브쿼리, CTE)
- 대규모 데이터셋 JOIN (수백만-천만 행)

**실행:**
```bash
./03-join-performance.sh
```

**주요 학습 포인트:**
- 해시 테이블 구축 및 프로빙 최적화
- 대형 JOIN의 메모리 효율성 향상
- 다중 테이블 JOIN 쿼리 플래닝 개선
- JOIN 조건의 최적 순서
- RIGHT vs LEFT 테이블 선택 전략
- CTE(Common Table Expression) 활용

**실무 활용:**
- E-커머스 고객 및 주문 분석
- 다차원 비즈니스 인텔리전스 대시보드
- 고객 세그멘테이션 및 코호트 분석
- 공급망 및 재고 관리 리포팅
- 재무 리포팅 및 거래 조정
- 마케팅 어트리뷰션 및 캠페인 성능 분석

**성능 최적화:**
- 작은 테이블을 RIGHT 테이블로 배치
- JOIN 키에 적절한 데이터 타입 사용
- 불필요한 컬럼 SELECT 하지 않기
- WHERE 조건으로 JOIN 전 데이터 필터링

---

### 4. Bulk UPDATE Performance (04-bulk-update)

**새로운 기능:** PostgreSQL 대비 최대 4000배 빠른 대량 업데이트

**테스트 내용:**
- 대규모 bulk UPDATE (1000만 행)
- 복잡한 WHERE 조건의 UPDATE
- 다중 컬럼 동시 UPDATE
- CASE 문을 이용한 조건부 UPDATE
- 집계 결과를 이용한 UPDATE
- 성능 비교 및 벤치마킹

**실행:**
```bash
./04-bulk-update.sh
```

**주요 학습 포인트:**
- Patch-part 메커니즘으로 전체 테이블 재작성 불필요
- 수백만 행을 초 단위로 업데이트 가능
- 복잡한 조건부 업데이트 효율적 처리
- 서브쿼리를 이용한 JOIN-like UPDATE
- 비동기 mutation으로 시스템 부하 최소화
- ALTER TABLE UPDATE 문법 활용

**실무 활용:**
- 실시간 재고 동기화 및 가격 조정
- 소매업: 일일 마감 가격 업데이트 및 프로모션
- 금융: 대량 계좌 잔액 조정
- 게임: 플레이어 통계 및 리더보드 업데이트
- IoT: 디바이스 구성 및 상태 대량 업데이트
- 데이터 마이그레이션: 레거시 시스템 현대화
- 데이터 품질: 대량 정정 및 정규화

**성능 비교:**
| Database | 수백만 행 업데이트 시간 | 기술 | 성능 |
|----------|---------------------|------|------|
| ClickHouse 25.7 | 초 단위 | Patch-part 메커니즘 | 4000배 빠름 |
| PostgreSQL | 시간 단위 | 전체 행 재작성 | 기준 |

---

### 5. AI-Powered SQL Generation (Feature Description)

**새로운 기능:** OpenAI 또는 Anthropic API를 이용한 자연어 SQL 생성

**설명:**
ClickHouse 25.7은 `??` prefix를 사용하여 자연어를 SQL로 변환하는 AI 기반 SQL 생성 기능을 제공합니다.

**사용 방법:**
```sql
-- OpenAI API 사용
SET openai_api_key = 'your-api-key';
?? show me top 10 customers by revenue

-- Anthropic API 사용
SET anthropic_api_key = 'your-api-key';
?? calculate monthly growth rate for each product category
```

**주요 특징:**
- 자연어를 SQL 쿼리로 자동 변환
- 테이블 스키마 자동 분석
- 복잡한 집계 및 JOIN 쿼리 생성
- 학습 곡선 단축 및 생산성 향상
- 비개발자도 데이터 분석 가능

**제약 사항:**
- OpenAI 또는 Anthropic API 키 필요
- API 호출 비용 발생
- 네트워크 연결 필요
- 생성된 쿼리 검증 권장

**실무 활용:**
- 비즈니스 분석가의 셀프 서비스 분석
- 빠른 프로토타이핑 및 탐색적 분석
- 교육 및 SQL 학습 보조
- 복잡한 쿼리의 초안 생성

**참고:** 이 기능은 API 키가 필요하므로 이 lab에서는 실행 가능한 테스트를 제공하지 않습니다. 위의 예제를 참고하여 직접 테스트해보세요.

## 🔧 Management

### ClickHouse Connection Info

- **Web UI**: http://localhost:2507/play
- **HTTP API**: http://localhost:2507
- **TCP**: localhost:25071
- **User**: default (no password)

### Useful Commands

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2507

# 로그 확인
docker logs clickhouse-25-7

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

## 📂 File Structure

```
25.7/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.7 설치 스크립트
├── 01-sql-update-delete.sh        # SQL UPDATE/DELETE 테스트 실행
├── 01-sql-update-delete.sql       # SQL UPDATE/DELETE SQL
├── 02-count-optimization.sh       # count() 최적화 테스트 실행
├── 02-count-optimization.sql      # count() 최적화 SQL
├── 03-join-performance.sh         # JOIN 성능 테스트 실행
├── 03-join-performance.sql        # JOIN 성능 SQL
├── 04-bulk-update.sh              # Bulk UPDATE 테스트 실행
└── 04-bulk-update.sql             # Bulk UPDATE SQL
```

## 🎓 Learning Path

### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-count-optimization** - 기본 집계 함수부터 시작
3. **01-sql-update-delete** - UPDATE/DELETE 기초 학습

### 중급 사용자
1. **03-join-performance** - JOIN 최적화 이해
2. **04-bulk-update** - 대량 데이터 처리 학습
3. AI-Powered SQL 기능 탐색 (API 키 필요)

### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 최적화
- 실시간 데이터 파이프라인 설계

## 💡 Feature Comparison

### ClickHouse 25.7 vs Previous Versions

| Feature | Before 25.7 | ClickHouse 25.7 | Improvement |
|---------|-------------|-----------------|-------------|
| UPDATE/DELETE | Slow (full rewrites) | Patch-part mechanism | Up to 1000x faster |
| count() aggregation | Standard performance | Optimized | 20-30% faster |
| JOIN operations | Good performance | Enhanced | Up to 1.8x faster |
| Bulk UPDATE | Slow for large datasets | Highly optimized | Up to 4000x vs PostgreSQL |
| SQL Generation | Manual only | AI-powered (optional) | Natural language to SQL |

### UPDATE Performance Comparison

| Operation | Traditional RDBMS | ClickHouse 25.7 | Performance Gain |
|-----------|------------------|-----------------|-----------------|
| Single row UPDATE | Milliseconds | Microseconds | 100-1000x |
| Bulk UPDATE (1M rows) | Hours | Seconds | 4000x |
| Complex conditional UPDATE | Very slow | Fast | 1000x |

## 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.7 Release](https://clickhouse.com/blog/clickhouse-release-25-07)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

## 📝 Notes

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다
- AI-Powered SQL 기능은 API 키가 필요합니다

## 🔒 Security Considerations

**UPDATE/DELETE 연산 사용 시:**
- 프로덕션 환경에서는 신중하게 테스트
- WHERE 조건 없는 UPDATE는 전체 테이블 영향
- 백업 후 대량 업데이트 수행 권장
- Mutation 큐 모니터링

**AI-Powered SQL 사용 시:**
- API 키는 환경 변수로 안전하게 관리
- 생성된 SQL은 실행 전 검증
- 민감한 데이터에 대한 접근 제어
- API 사용량 및 비용 모니터링

## ⚡ Performance Tips

**UPDATE/DELETE 최적화:**
- 적절한 WHERE 조건으로 범위 제한
- 파티션 키를 이용한 효율적인 필터링
- 인덱스 키를 WHERE 조건에 활용
- Mutation 상태 모니터링 (system.mutations 테이블)

**count() 최적화:**
- 가능하면 count() 사용 (count(column) 대신)
- 적절한 ORDER BY 키로 인덱스 활용
- 파티션을 이용한 쿼리 범위 제한
- Materialized View로 사전 집계

**JOIN 최적화:**
- 작은 테이블을 RIGHT 테이블로
- JOIN 키에 적절한 데이터 타입
- WHERE로 JOIN 전 데이터 필터링
- 불필요한 컬럼 제거

**Bulk UPDATE 최적화:**
- 배치 크기 조정으로 메모리 효율성
- 오프피크 시간에 대량 업데이트 수행
- 파티션별로 업데이트 분산
- 진행 상황 모니터링

## 🚀 Production Deployment

### Migration Strategy

1. **테스트 환경에서 검증**
   - 모든 UPDATE/DELETE 쿼리 테스트
   - 성능 벤치마킹
   - 롤백 계획 수립

2. **점진적 롤아웃**
   - 작은 테이블부터 시작
   - 모니터링 및 성능 측정
   - 문제 발생 시 즉시 롤백

3. **모니터링**
   - Mutation 큐 상태 확인
   - 리소스 사용량 모니터링
   - 쿼리 성능 추적

### Best Practices

```sql
-- Mutation 상태 확인
SELECT *
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time DESC;

-- 실행 중인 쿼리 모니터링
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- 테이블 파트 상태
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;
```

## 🤝 Contributing

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

## 📄 License

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../README.md).
