# ClickHouse Projection Lab

ClickHouse의 Projection 기능을 학습하고 성능을 테스트하는 실습 환경입니다.

## 📚 개요

Projection은 ClickHouse의 강력한 성능 최적화 기능으로, 테이블 내에 미리 집계된 데이터를 저장하여 쿼리 성능을 크게 향상시킵니다. 이 실습에서는 Projection과 Materialized View를 비교하고 실제 성능 차이를 확인할 수 있습니다.

## 🎯 학습 목표

- Projection의 개념과 동작 원리 이해
- Projection과 Materialized View의 차이점 파악
- 실제 데이터를 통한 성능 비교
- Projection 관리 및 모니터링 방법 습득

## 📁 파일 구성

```
sql-lab-projection/
├── README.md                    # 이 파일
├── 01-setup.sql                 # 환경 준비 및 데이터 생성
├── 02-add-projections.sql       # Projection 생성 및 구체화
├── 03-materialized-view.sql     # Materialized View 생성 (비교용)
├── 04-performance-tests.sql     # 성능 테스트 쿼리
├── 05-metadata-analysis.sql     # 메타데이터 및 스토리지 분석
├── 06-monitoring.sql            # 쿼리 성능 모니터링
└── 99-cleanup.sql               # 정리 스크립트
```

## 🚀 실습 순서

### 1. 환경 준비 및 데이터 생성

```bash
clickhouse-client < 01-setup.sql
```

- `projection_test` 데이터베이스 생성
- `sales_events` 테이블 생성 (1000만 건의 이벤트 데이터)
- 테스트 데이터 삽입

**소요 시간**: 약 1-2분

### 2. Projection 생성

```bash
clickhouse-client < 02-add-projections.sql
```

- `category_analysis` Projection: 카테고리별 월별 집계
- `brand_daily_stats` Projection: 브랜드별 일별 통계
- Projection 구체화 (MATERIALIZE)

**소요 시간**: 약 2-3분 (데이터 구체화 포함)

**참고**: 동기 구체화를 원하는 경우 스크립트 내의 주석을 해제하세요.

### 3. Materialized View 생성 (비교용)

```bash
clickhouse-client < 03-materialized-view.sql
```

- 동일한 집계를 수행하는 Materialized View 생성
- 기존 데이터 적재

**소요 시간**: 약 1분

### 4. 성능 테스트

```bash
clickhouse-client < 04-performance-tests.sql
```

다음 시나리오를 테스트합니다:
- Projection 활성화 vs 비활성화 비교
- Materialized View와의 성능 비교
- 브랜드 분석, 다차원 분석 등 다양한 쿼리 패턴
- EXPLAIN을 통한 실행 계획 분석

**주요 확인 사항**:
- 쿼리 실행 시간
- 읽은 행 수 (read_rows)
- 읽은 데이터 크기 (read_bytes)
- Projection 자동 선택 여부

### 5. 메타데이터 분석

```bash
clickhouse-client < 05-metadata-analysis.sql
```

- 테이블 및 Projection 크기 확인
- 파티션별 통계
- 컬럼별 압축 비율
- Projection 목록 조회

### 6. 성능 모니터링

```bash
clickhouse-client < 06-monitoring.sql
```

- 최근 쿼리 성능 확인
- Projection 사용 여부 확인
- 쿼리 통계 비교
- Mutation 진행 상태 확인

### 7. 정리

```bash
clickhouse-client < 99-cleanup.sql
```

모든 테스트 데이터와 테이블을 삭제합니다.

## 🔍 핵심 개념

### Projection vs Materialized View

| 특징 | Projection | Materialized View |
|------|-----------|-------------------|
| 저장 위치 | 원본 테이블 내부 | 별도 테이블 |
| 자동 선택 | 자동 (쿼리 최적화) | 수동 (명시적 쿼리) |
| 데이터 일관성 | 항상 동기화 | 비동기 업데이트 |
| 스토리지 오버헤드 | 중간 | 높음 |
| 관리 복잡도 | 낮음 | 높음 |

### Projection 사용 시기

✅ **적합한 경우**:
- 특정 집계 쿼리가 자주 실행됨
- 원본 데이터와 항상 일관성 유지 필요
- 관리 복잡도를 낮추고 싶음

❌ **부적합한 경우**:
- 매우 복잡한 변환 로직 필요
- 여러 테이블 조인 필요
- 데이터 지연 허용 가능

## 💡 팁

### 성능 비교 방법

1. **쿼리 실행 시간 측정**:
```sql
SELECT ... SETTINGS allow_experimental_projection_optimization = 1;
SELECT ... SETTINGS allow_experimental_projection_optimization = 0;
```

2. **실행 계획 확인**:
```sql
EXPLAIN indexes = 1, description = 1
SELECT ...;
```

3. **모니터링**:
```sql
SELECT
    ProfileEvents['SelectedProjectionParts'] as projection_used,
    query_duration_ms,
    read_rows
FROM system.query_log
WHERE query_id = 'YOUR_QUERY_ID';
```

### Projection 구체화 전략

- **비동기 구체화** (기본): 백그라운드에서 점진적으로 구체화
  ```sql
  MATERIALIZE PROJECTION projection_name;
  ```

- **동기 구체화**: 완료될 때까지 대기
  ```sql
  MATERIALIZE PROJECTION projection_name SETTINGS mutations_sync = 1;
  ```

### 주의사항

1. Projection은 스토리지 공간을 추가로 사용합니다
2. INSERT 성능에 약간의 영향을 줄 수 있습니다
3. ClickHouse 버전에 따라 기능이 다를 수 있습니다
4. `allow_experimental_projection_optimization` 설정 확인 필요

## 📊 예상 결과

### 성능 개선 예시

일반적으로 다음과 같은 성능 향상을 기대할 수 있습니다:

- **쿼리 실행 시간**: 10-100배 감소
- **읽은 행 수**: 100-1000배 감소
- **메모리 사용량**: 50-90% 감소

실제 결과는 데이터 크기, 쿼리 패턴, 하드웨어 사양에 따라 달라질 수 있습니다.

## 🔧 문제 해결

### Projection이 자동으로 선택되지 않는 경우

1. 설정 확인:
```sql
SET allow_experimental_projection_optimization = 1;
```

2. Projection 구체화 상태 확인:
```sql
SELECT * FROM system.mutations WHERE table = 'sales_events';
```

3. 실행 계획 확인:
```sql
EXPLAIN indexes = 1 SELECT ...;
```

### 메모리 부족 오류

대용량 데이터 삽입 시 메모리 부족이 발생하면:
- 데이터를 여러 배치로 나누어 삽입
- `max_memory_usage` 설정 조정

## 📚 참고 자료

- [ClickHouse Projections 공식 문서](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#projections)
- [Performance Optimization Guide](https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler)

## 🤝 기여

이슈나 개선 사항이 있으면 언제든지 제안해주세요!
