# ClickHouse Projection Custom Settings Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning how to configure custom settings (especially index_granularity) for ClickHouse Projections.

### 🎯 Purpose

This lab provides practical experience with Projection custom settings in ClickHouse:
- Understanding how to apply custom settings to Projections (25.12+ feature)
- Comparing different index_granularity values for Projections
- Measuring the impact of granularity on point query performance
- Learning best practices for choosing granularity based on query patterns

Whether you're optimizing point query performance with Projections or choosing the right granularity for different access patterns, this lab offers structured exercises with real data and measurable results.

### 📁 File Structure

```
projection-customsettings/
├── README.md                      # This file
├── 01-setup.sql                   # Database and table creation
├── 02-add-projections.sql         # Create projections with custom settings
├── 03-granularity-comparison.sql  # Compare different granularity values
├── 04-performance-tests.sql       # Performance testing queries
├── 05-monitoring.sql              # Query and projection monitoring
└── 99-cleanup.sql                 # Cleanup script
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd workload/projection-customsettings

clickhouse-client < 01-setup.sql
clickhouse-client < 02-add-projections.sql
clickhouse-client < 03-granularity-comparison.sql
clickhouse-client < 04-performance-tests.sql
clickhouse-client < 05-monitoring.sql

# Cleanup when done
clickhouse-client < 99-cleanup.sql
```

### 📖 Detailed Lab Steps

#### 1. Environment Setup

```bash
clickhouse-client < 01-setup.sql
```

**What it does**:
- Creates `projection_granularity_test` database
- Creates `events` table with default granularity (8192)
- Inserts 1 million sample event records

**Expected time**: ~30-60 seconds

---

#### 2. Create Projections with Custom Settings

```bash
clickhouse-client < 02-add-projections.sql
```

**What it does**:
- Creates basic projection (inherits base table granularity)
- Shows syntax for custom settings (25.12+ only)
- Examples of multiple projections with different granularity values
- Materializes projections

**Expected time**: ~1-2 minutes

**Version Note**:
- ClickHouse 25.10 and below: WITH SETTINGS syntax not supported
- ClickHouse 25.12+: WITH SETTINGS syntax available

---

#### 3. Granularity Comparison Analysis

```bash
clickhouse-client < 03-granularity-comparison.sql
```

**What it does**:
- Uses existing `granularity_test` database for comparison
- Tests G=256, 1024, 4096, 8192 tables
- Analyzes storage overhead and index statistics
- Calculates marks and granule efficiency

**Expected time**: < 10 seconds

---

#### 4. Performance Testing

```bash
clickhouse-client < 04-performance-tests.sql
```

**Test scenarios**:
- Point query performance tests (single ID lookup)
- Range query performance tests
- Aggregation query comparison
- EXPLAIN analysis for execution plans

**Key metrics to observe**:
- Query execution time
- Rows read per query
- Marks scanned
- Index efficiency

---

#### 5. Monitoring and Analysis

```bash
clickhouse-client < 05-monitoring.sql
```

**What it monitors**:
- Recent query performance from query_log
- Projection usage statistics
- Parts and merge activity
- Projection materialization status

---

#### 6. Cleanup

```bash
clickhouse-client < 99-cleanup.sql
```

Removes all test data and tables.

### 🔍 Key Concepts

#### Projection Custom Settings (25.12+)

Starting with ClickHouse 25.12, you can specify custom settings for individual projections:

```sql
ALTER TABLE events
ADD PROJECTION user_lookup (
    SELECT * ORDER BY user_id, event_time
) WITH SETTINGS (
    index_granularity = 256
);
```

#### Index Granularity Effects

| Granularity | Marks | Index Overhead | Point Query | Range Scan |
|-------------|-------|----------------|-------------|------------|
| 256         | Many  | High (~0.09%)  | Very Fast   | Slow       |
| 1024        | Medium| Medium (~0.02%)| Fast        | Medium     |
| 4096        | Few   | Low (~0.005%)  | Medium      | Fast       |
| 8192        | Very Few| Very Low (~0.004%)| Slow   | Very Fast  |

#### Recommended Settings by Query Pattern

- **Point Query** (single key lookup): 256~512
- **Small Range Query**: 512~1024
- **Medium Range Query**: 1024~2048
- **Large Range Scan**: 4096~8192
- **Full Table Scan**: 8192~16384

### 📊 Expected Results

#### Point Query Performance (player_id = 500000)

```
G=256:  ~256 rows read
G=8192: ~8192 rows read
→ 32x performance difference
```

#### Storage Overhead (2M rows)

```
G=256:  7,814 marks, 66.34 MiB, 0.09% index overhead
G=8192:   245 marks, 54.02 MiB, 0.004% index overhead
```

### 💡 Best Practices

#### Multi-Projection Strategy

For tables with diverse query patterns, create multiple projections:

```sql
-- Projection 1: Point Query optimization
ADD PROJECTION user_lookup (...) WITH SETTINGS (index_granularity = 256);

-- Projection 2: Session analysis optimization
ADD PROJECTION session_analysis (...) WITH SETTINGS (index_granularity = 512);

-- Projection 3: Aggregation optimization
ADD PROJECTION event_stats (...) WITH SETTINGS (index_granularity = 2048);
```

#### When to Use Smaller Granularity

✅ **Good for**:
- Frequent point queries by specific keys
- Low-latency requirements
- High-cardinality keys
- User/session lookup patterns

❌ **Not suitable for**:
- Primarily analytical/scan queries
- Memory-constrained environments
- Very large tables (billions of rows)

### ⚠️ Version Compatibility

- **25.10 and below**: WITH SETTINGS syntax not supported
  - Projections inherit base table's granularity
- **25.12 and above**: WITH SETTINGS syntax supported
  - Each projection can have independent granularity

### 🔧 Troubleshooting

#### Projection Not Created

Check ClickHouse version:
```sql
SELECT version();
```

If version < 25.12, use basic projection syntax without WITH SETTINGS.

#### High Memory Usage

Monitor index memory consumption:
```sql
SELECT
    table,
    name as projection_name,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) as index_memory
FROM system.projection_parts
WHERE database = 'projection_granularity_test'
GROUP BY table, name;
```

### 🛠 Prerequisites

- ClickHouse server (local or cloud)
- ClickHouse client installed
- Basic SQL knowledge
- Sufficient disk space (~200MB for test data)

### 📚 Reference

- [ClickHouse Projections](https://clickhouse.com/docs/en/sql-reference/statements/alter/projection)
- [Index Granularity](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- [Performance Optimization](https://clickhouse.com/docs/en/operations/optimizing-performance)

### 📝 License

MIT License

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2025-01-09

---

## 한국어

ClickHouse Projection에 커스텀 설정(특히 index_granularity)을 적용하는 방법을 학습하는 실습 환경입니다.

### 🎯 목적

이 랩은 ClickHouse Projection 커스텀 설정에 대한 실무 경험을 제공합니다:
- Projection에 커스텀 설정을 적용하는 방법 이해 (25.12+ 기능)
- Projection에 대한 다양한 index_granularity 값 비교
- Granularity가 point query 성능에 미치는 영향 측정
- 쿼리 패턴에 따른 granularity 선택 모범 사례 학습

Projection으로 point query 성능을 최적화하거나 다양한 액세스 패턴에 적합한 granularity를 선택하려는 경우, 이 랩은 실제 데이터와 측정 가능한 결과를 통한 구조화된 연습을 제공합니다.

### 📁 파일 구성

```
projection-customsettings/
├── README.md                      # 이 파일
├── 01-setup.sql                   # 데이터베이스 및 테이블 생성
├── 02-add-projections.sql         # 커스텀 설정으로 Projection 생성
├── 03-granularity-comparison.sql  # 다양한 granularity 값 비교
├── 04-performance-tests.sql       # 성능 테스트 쿼리
├── 05-monitoring.sql              # 쿼리 및 Projection 모니터링
└── 99-cleanup.sql                 # 정리 스크립트
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd workload/projection-customsettings

clickhouse-client < 01-setup.sql
clickhouse-client < 02-add-projections.sql
clickhouse-client < 03-granularity-comparison.sql
clickhouse-client < 04-performance-tests.sql
clickhouse-client < 05-monitoring.sql

# 완료 후 정리
clickhouse-client < 99-cleanup.sql
```

### 📖 상세 실습 단계

#### 1. 환경 준비

```bash
clickhouse-client < 01-setup.sql
```

**수행 작업**:
- `projection_granularity_test` 데이터베이스 생성
- 기본 granularity(8192)를 가진 `events` 테이블 생성
- 100만 개의 샘플 이벤트 레코드 삽입

**예상 시간**: 약 30-60초

---

#### 2. 커스텀 설정으로 Projection 생성

```bash
clickhouse-client < 02-add-projections.sql
```

**수행 작업**:
- 기본 Projection 생성 (베이스 테이블 granularity 상속)
- 커스텀 설정 문법 예시 (25.12+ 전용)
- 다양한 granularity 값을 가진 여러 Projection 예제
- Projection 구체화

**예상 시간**: 약 1-2분

**버전 참고사항**:
- ClickHouse 25.10 이하: WITH SETTINGS 문법 미지원
- ClickHouse 25.12+: WITH SETTINGS 문법 사용 가능

---

#### 3. Granularity 비교 분석

```bash
clickhouse-client < 03-granularity-comparison.sql
```

**수행 작업**:
- 비교를 위해 기존 `granularity_test` 데이터베이스 활용
- G=256, 1024, 4096, 8192 테이블 테스트
- 스토리지 오버헤드 및 인덱스 통계 분석
- Marks 및 granule 효율성 계산

**예상 시간**: 10초 미만

---

#### 4. 성능 테스트

```bash
clickhouse-client < 04-performance-tests.sql
```

**테스트 시나리오**:
- Point query 성능 테스트 (단일 ID 조회)
- Range query 성능 테스트
- 집계 쿼리 비교
- 실행 계획을 위한 EXPLAIN 분석

**주요 확인 지표**:
- 쿼리 실행 시간
- 쿼리당 읽은 행 수
- 스캔한 Marks
- 인덱스 효율성

---

#### 5. 모니터링 및 분석

```bash
clickhouse-client < 05-monitoring.sql
```

**모니터링 내용**:
- query_log의 최근 쿼리 성능
- Projection 사용 통계
- Parts 및 Merge 활동
- Projection 구체화 상태

---

#### 6. 정리

```bash
clickhouse-client < 99-cleanup.sql
```

모든 테스트 데이터와 테이블을 삭제합니다.

### 🔍 핵심 개념

#### Projection 커스텀 설정 (25.12+)

ClickHouse 25.12부터 개별 Projection에 대해 커스텀 설정을 지정할 수 있습니다:

```sql
ALTER TABLE events
ADD PROJECTION user_lookup (
    SELECT * ORDER BY user_id, event_time
) WITH SETTINGS (
    index_granularity = 256
);
```

#### Index Granularity 효과

| Granularity | Marks | 인덱스 오버헤드 | Point Query | Range Scan |
|-------------|-------|----------------|-------------|------------|
| 256         | 많음   | 높음 (~0.09%)  | 매우 빠름    | 느림       |
| 1024        | 중간   | 중간 (~0.02%)  | 빠름        | 보통       |
| 4096        | 적음   | 낮음 (~0.005%) | 보통        | 빠름       |
| 8192        | 매우적음| 매우낮음 (~0.004%)| 느림     | 매우 빠름  |

#### 쿼리 패턴별 권장 설정

- **Point Query** (단일 키 조회): 256~512
- **Small Range Query**: 512~1024
- **Medium Range Query**: 1024~2048
- **Large Range Scan**: 4096~8192
- **Full Table Scan**: 8192~16384

### 📊 예상 결과

#### Point Query 성능 (player_id = 500000)

```
G=256:  약 256 rows 읽음
G=8192: 약 8192 rows 읽음
→ 32배 성능 차이
```

#### 스토리지 오버헤드 (200만 rows)

```
G=256:  7,814 marks, 66.34 MiB, 0.09% 인덱스 오버헤드
G=8192:   245 marks, 54.02 MiB, 0.004% 인덱스 오버헤드
```

### 💡 모범 사례

#### 다중 Projection 전략

다양한 쿼리 패턴을 가진 테이블의 경우 여러 Projection 생성:

```sql
-- Projection 1: Point Query 최적화
ADD PROJECTION user_lookup (...) WITH SETTINGS (index_granularity = 256);

-- Projection 2: Session 분석 최적화
ADD PROJECTION session_analysis (...) WITH SETTINGS (index_granularity = 512);

-- Projection 3: 집계 최적화
ADD PROJECTION event_stats (...) WITH SETTINGS (index_granularity = 2048);
```

#### 작은 Granularity 사용 시기

✅ **적합한 경우**:
- 특정 키로 빈번한 point query
- 낮은 지연 시간 요구사항
- 높은 카디널리티 키
- 사용자/세션 조회 패턴

❌ **부적합한 경우**:
- 주로 분석/스캔 쿼리
- 메모리 제약이 있는 환경
- 매우 큰 테이블 (수십억 행)

### ⚠️ 버전 호환성

- **25.10 이하**: WITH SETTINGS 문법 미지원
  - Projection은 베이스 테이블의 granularity 상속
- **25.12 이상**: WITH SETTINGS 문법 지원
  - 각 Projection이 독립적인 granularity를 가질 수 있음

### 🔧 트러블슈팅

#### Projection이 생성되지 않음

ClickHouse 버전 확인:
```sql
SELECT version();
```

버전 < 25.12인 경우 WITH SETTINGS 없이 기본 Projection 문법 사용.

#### 높은 메모리 사용량

인덱스 메모리 소비 모니터링:
```sql
SELECT
    table,
    name as projection_name,
    formatReadableSize(sum(primary_key_bytes_in_memory_allocated)) as index_memory
FROM system.projection_parts
WHERE database = 'projection_granularity_test'
GROUP BY table, name;
```

### 🛠 사전 요구사항

- ClickHouse 서버 (로컬 또는 클라우드)
- ClickHouse 클라이언트 설치
- 기본 SQL 지식
- 충분한 디스크 공간 (테스트 데이터용 ~200MB)

### 📚 참고 자료

- [ClickHouse Projections](https://clickhouse.com/docs/en/sql-reference/statements/alter/projection)
- [Index Granularity](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- [Performance Optimization](https://clickhouse.com/docs/en/operations/optimizing-performance)

### 📝 라이선스

MIT License

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2025-01-09
