# ClickHouse Projection Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning ClickHouse Projection features and testing performance improvements.

### 🎯 Purpose

This lab provides practical experience with ClickHouse Projections:
- Understanding Projection concepts and operation principles
- Comparing Projection vs Materialized View
- Measuring real-world performance improvements
- Learning Projection management and monitoring techniques

Whether you're optimizing query performance or choosing between Projection and Materialized Views, this lab offers structured exercises with real data and measurable results.

### 📁 File Structure

```
projection/
├── README.md                    # This file
├── 01-setup.sql                 # Environment setup and data generation
├── 02-add-projections.sql       # Create and materialize projections
├── 03-materialized-view.sql     # Create materialized views (for comparison)
├── 04-performance-tests.sql     # Performance test queries
├── 05-metadata-analysis.sql     # Metadata and storage analysis
├── 06-monitoring.sql            # Query performance monitoring
└── 99-cleanup.sql               # Cleanup script
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd workload/projection

clickhouse-client < 01-setup.sql
clickhouse-client < 02-add-projections.sql
clickhouse-client < 03-materialized-view.sql
clickhouse-client < 04-performance-tests.sql
clickhouse-client < 05-metadata-analysis.sql
clickhouse-client < 06-monitoring.sql

# Cleanup when done
clickhouse-client < 99-cleanup.sql
```

### 📖 Detailed Lab Steps

#### 1. Environment Setup and Data Generation

```bash
clickhouse-client < 01-setup.sql
```

**What it does**:
- Creates `projection_test` database
- Creates `sales_events` table (10 million event records)
- Inserts test data

**Expected time**: ~1-2 minutes

---

#### 2. Create Projections

```bash
clickhouse-client < 02-add-projections.sql
```

**What it does**:
- Creates `category_analysis` Projection: Monthly aggregation by category
- Creates `brand_daily_stats` Projection: Daily statistics by brand
- Materializes projections (MATERIALIZE)

**Expected time**: ~2-3 minutes (including materialization)

**Note**: For synchronous materialization, uncomment the appropriate lines in the script.

---

#### 3. Create Materialized Views (For Comparison)

```bash
clickhouse-client < 03-materialized-view.sql
```

**What it does**:
- Creates Materialized View performing same aggregations
- Loads existing data

**Expected time**: ~1 minute

---

#### 4. Performance Testing

```bash
clickhouse-client < 04-performance-tests.sql
```

**Test scenarios**:
- Projection enabled vs disabled comparison
- Performance comparison with Materialized Views
- Various query patterns: brand analysis, multi-dimensional analysis
- Execution plan analysis with EXPLAIN

**Key metrics to observe**:
- Query execution time
- Rows read (read_rows)
- Data size read (read_bytes)
- Automatic projection selection

---

#### 5. Metadata Analysis

```bash
clickhouse-client < 05-metadata-analysis.sql
```

**What it analyzes**:
- Table and projection sizes
- Statistics by partition
- Compression ratio by column
- Projection list

---

#### 6. Performance Monitoring

```bash
clickhouse-client < 06-monitoring.sql
```

**What it monitors**:
- Recent query performance
- Projection usage verification
- Query statistics comparison
- Mutation progress status

---

#### 7. Cleanup

```bash
clickhouse-client < 99-cleanup.sql
```

Removes all test data and tables.

### 🔍 Key Concepts

#### Projection vs Materialized View

| Feature | Projection | Materialized View |
|---------|-----------|-------------------|
| Storage Location | Inside original table | Separate table |
| Automatic Selection | Automatic (query optimization) | Manual (explicit query) |
| Data Consistency | Always synchronized | Asynchronous updates |
| Storage Overhead | Medium | High |
| Management Complexity | Low | High |

#### When to Use Projection

✅ **Good for**:
- Specific aggregation queries run frequently
- Always require consistency with source data
- Want to reduce management complexity

❌ **Not suitable for**:
- Very complex transformation logic needed
- Multiple table joins required
- Data latency is acceptable

### 💡 Tips

#### Performance Comparison Methods

1. **Measure Query Execution Time**:
```sql
SELECT ... SETTINGS allow_experimental_projection_optimization = 1;
SELECT ... SETTINGS allow_experimental_projection_optimization = 0;
```

2. **Check Execution Plan**:
```sql
EXPLAIN indexes = 1, description = 1
SELECT ...;
```

3. **Monitor Usage**:
```sql
SELECT
    ProfileEvents['SelectedProjectionParts'] as projection_used,
    query_duration_ms,
    read_rows
FROM system.query_log
WHERE query_id = 'YOUR_QUERY_ID';
```

#### Projection Materialization Strategy

- **Asynchronous materialization** (default): Materializes gradually in background
  ```sql
  MATERIALIZE PROJECTION projection_name;
  ```

- **Synchronous materialization**: Waits until completion
  ```sql
  MATERIALIZE PROJECTION projection_name SETTINGS mutations_sync = 1;
  ```

#### Important Notes

1. Projections consume additional storage space
2. May slightly impact INSERT performance
3. Features may vary by ClickHouse version
4. Check `allow_experimental_projection_optimization` setting

### 📊 Expected Results

#### Performance Improvement Examples

Typical performance improvements you can expect:

- **Query execution time**: 10-100x reduction
- **Rows read**: 100-1000x reduction
- **Memory usage**: 50-90% reduction

Actual results may vary based on data size, query patterns, and hardware specifications.

### 🔧 Troubleshooting

#### Projection Not Automatically Selected

1. Check settings:
```sql
SET allow_experimental_projection_optimization = 1;
```

2. Verify projection materialization status:
```sql
SELECT * FROM system.mutations WHERE table = 'sales_events';
```

3. Check execution plan:
```sql
EXPLAIN indexes = 1 SELECT ...;
```

#### Out of Memory Error

If memory issues occur during large data inserts:
- Split data into multiple batches
- Adjust `max_memory_usage` setting

### 🛠 Prerequisites

- ClickHouse server (local or cloud)
- ClickHouse client installed
- Basic SQL knowledge
- Sufficient disk space (~500MB for test data)

### 📚 Reference

- [ClickHouse Projections Official Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#projections)
- [Performance Optimization Guide](https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler)

### 📝 License

[MIT](../../LICENSE) — same as the rest of the repository.

### 👤 Author

Ken (ClickHouse Solution Architect)

---

## 한국어

ClickHouse의 Projection 기능을 학습하고 성능을 테스트하는 실습 환경입니다.

### 🎯 목적

이 랩은 ClickHouse Projection에 대한 실무 경험을 제공합니다:
- Projection의 개념과 동작 원리 이해
- Projection과 Materialized View의 차이점 파악
- 실제 데이터를 통한 성능 비교
- Projection 관리 및 모니터링 방법 습득

쿼리 성능을 최적화하거나 Projection과 Materialized View 중 선택하려는 경우, 이 랩은 실제 데이터와 측정 가능한 결과를 통한 구조화된 연습을 제공합니다.

### 📁 파일 구성

```
projection/
├── README.md                    # 이 파일
├── 01-setup.sql                 # 환경 준비 및 데이터 생성
├── 02-add-projections.sql       # Projection 생성 및 구체화
├── 03-materialized-view.sql     # Materialized View 생성 (비교용)
├── 04-performance-tests.sql     # 성능 테스트 쿼리
├── 05-metadata-analysis.sql     # 메타데이터 및 스토리지 분석
├── 06-monitoring.sql            # 쿼리 성능 모니터링
└── 99-cleanup.sql               # 정리 스크립트
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd workload/projection

clickhouse-client < 01-setup.sql
clickhouse-client < 02-add-projections.sql
clickhouse-client < 03-materialized-view.sql
clickhouse-client < 04-performance-tests.sql
clickhouse-client < 05-metadata-analysis.sql
clickhouse-client < 06-monitoring.sql

# 완료 후 정리
clickhouse-client < 99-cleanup.sql
```

### 📖 상세 실습 단계

#### 1. 환경 준비 및 데이터 생성

```bash
clickhouse-client < 01-setup.sql
```

**수행 작업**:
- `projection_test` 데이터베이스 생성
- `sales_events` 테이블 생성 (1000만 건의 이벤트 데이터)
- 테스트 데이터 삽입

**소요 시간**: 약 1-2분

---

#### 2. Projection 생성

```bash
clickhouse-client < 02-add-projections.sql
```

**수행 작업**:
- `category_analysis` Projection: 카테고리별 월별 집계
- `brand_daily_stats` Projection: 브랜드별 일별 통계
- Projection 구체화 (MATERIALIZE)

**소요 시간**: 약 2-3분 (데이터 구체화 포함)

**참고**: 동기 구체화를 원하는 경우 스크립트 내의 주석을 해제하세요.

---

#### 3. Materialized View 생성 (비교용)

```bash
clickhouse-client < 03-materialized-view.sql
```

**수행 작업**:
- 동일한 집계를 수행하는 Materialized View 생성
- 기존 데이터 적재

**소요 시간**: 약 1분

---

#### 4. 성능 테스트

```bash
clickhouse-client < 04-performance-tests.sql
```

**테스트 시나리오**:
- Projection 활성화 vs 비활성화 비교
- Materialized View와의 성능 비교
- 브랜드 분석, 다차원 분석 등 다양한 쿼리 패턴
- EXPLAIN을 통한 실행 계획 분석

**주요 확인 사항**:
- 쿼리 실행 시간
- 읽은 행 수 (read_rows)
- 읽은 데이터 크기 (read_bytes)
- Projection 자동 선택 여부

---

#### 5. 메타데이터 분석

```bash
clickhouse-client < 05-metadata-analysis.sql
```

**분석 내용**:
- 테이블 및 Projection 크기 확인
- 파티션별 통계
- 컬럼별 압축 비율
- Projection 목록 조회

---

#### 6. 성능 모니터링

```bash
clickhouse-client < 06-monitoring.sql
```

**모니터링 내용**:
- 최근 쿼리 성능 확인
- Projection 사용 여부 확인
- 쿼리 통계 비교
- Mutation 진행 상태 확인

---

#### 7. 정리

```bash
clickhouse-client < 99-cleanup.sql
```

모든 테스트 데이터와 테이블을 삭제합니다.

### 🔍 핵심 개념

#### Projection vs Materialized View

| 특징 | Projection | Materialized View |
|------|-----------|-------------------|
| 저장 위치 | 원본 테이블 내부 | 별도 테이블 |
| 자동 선택 | 자동 (쿼리 최적화) | 수동 (명시적 쿼리) |
| 데이터 일관성 | 항상 동기화 | 비동기 업데이트 |
| 스토리지 오버헤드 | 중간 | 높음 |
| 관리 복잡도 | 낮음 | 높음 |

#### Projection 사용 시기

✅ **적합한 경우**:
- 특정 집계 쿼리가 자주 실행됨
- 원본 데이터와 항상 일관성 유지 필요
- 관리 복잡도를 낮추고 싶음

❌ **부적합한 경우**:
- 매우 복잡한 변환 로직 필요
- 여러 테이블 조인 필요
- 데이터 지연 허용 가능

### 💡 팁

#### 성능 비교 방법

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

#### Projection 구체화 전략

- **비동기 구체화** (기본): 백그라운드에서 점진적으로 구체화
  ```sql
  MATERIALIZE PROJECTION projection_name;
  ```

- **동기 구체화**: 완료될 때까지 대기
  ```sql
  MATERIALIZE PROJECTION projection_name SETTINGS mutations_sync = 1;
  ```

#### 주의사항

1. Projection은 스토리지 공간을 추가로 사용합니다
2. INSERT 성능에 약간의 영향을 줄 수 있습니다
3. ClickHouse 버전에 따라 기능이 다를 수 있습니다
4. `allow_experimental_projection_optimization` 설정 확인 필요

### 📊 예상 결과

#### 성능 개선 예시

일반적으로 다음과 같은 성능 향상을 기대할 수 있습니다:

- **쿼리 실행 시간**: 10-100배 감소
- **읽은 행 수**: 100-1000배 감소
- **메모리 사용량**: 50-90% 감소

실제 결과는 데이터 크기, 쿼리 패턴, 하드웨어 사양에 따라 달라질 수 있습니다.

### 🔧 문제 해결

#### Projection이 자동으로 선택되지 않는 경우

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

#### 메모리 부족 오류

대용량 데이터 삽입 시 메모리 부족이 발생하면:
- 데이터를 여러 배치로 나누어 삽입
- `max_memory_usage` 설정 조정

### 🛠 사전 요구사항

- ClickHouse 서버 (로컬 또는 클라우드)
- ClickHouse 클라이언트 설치
- 기본 SQL 지식
- 충분한 디스크 공간 (테스트 데이터용 ~500MB)

### 📚 참고 자료

- [ClickHouse Projections 공식 문서](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#projections)
- [Performance Optimization Guide](https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler)

### 📝 라이선스

[MIT](../../LICENSE) — same as the rest of the repository.

### 👤 작성자

Ken (ClickHouse Solution Architect)
