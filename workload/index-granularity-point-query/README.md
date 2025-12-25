# ClickHouse Index Granularity Point Query Benchmark

[English](#english) | [한국어](#한국어)

---

## English

A comprehensive benchmark test suite for comparing ClickHouse index_granularity settings and their impact on point query performance.

### 🎯 Purpose

This lab provides practical experience testing different index_granularity values in ClickHouse:
- **Granularity 256** - Optimized for precise point queries
- **Granularity 1024** - Good balance for point queries
- **Granularity 4096** - Balanced performance
- **Granularity 8192** - Default setting, optimized for scan queries

Whether you're optimizing point query performance or choosing the right granularity for your workload, this lab offers structured, step-by-step exercises to measure real-world performance characteristics.

### 📁 File Structure

```
index-granularity-point-query/
├── README.md                      # This file
├── 01-setup.sql                   # Database and table creation
├── 02-insert-data.sql             # Generate 2M rows test data
├── 03-metadata-check.sql          # Metadata and index statistics
├── 04-performance-test.sql        # Point query performance tests
├── 05-analyze-results.sql         # Performance analysis and comparison
└── 99-cleanup.sql                 # Cleanup script
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd workload/index-granularity-point-query

# Sequential execution
clickhouse-client --queries-file 01-setup.sql
clickhouse-client --queries-file 02-insert-data.sql
clickhouse-client --queries-file 03-metadata-check.sql
clickhouse-client --queries-file 04-performance-test.sql
clickhouse-client --queries-file 05-analyze-results.sql

# Cleanup when done
clickhouse-client --queries-file 99-cleanup.sql
```

Or execute all at once:

```bash
for file in 01-setup.sql 02-insert-data.sql 03-metadata-check.sql 04-performance-test.sql 05-analyze-results.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 Detailed Execution Steps

#### 1. Database Setup

```bash
clickhouse-client --queries-file 01-setup.sql
```

**What it does**:
- Creates `granularity_test` database
- Creates four test tables with different granularity settings:
  - `player_g256`: index_granularity = 256
  - `player_g1024`: index_granularity = 1024
  - `player_g4096`: index_granularity = 4096
  - `player_g8192`: index_granularity = 8192 (default)

**Expected time**: < 1 second

---

#### 2. Insert Test Data

```bash
clickhouse-client --queries-file 02-insert-data.sql
```

**What it does**:
- Inserts 2,000,000 rows into each table
- Simulates game player data with various attributes
- Copies data across all granularity tables

**Expected time**: 30-60 seconds (environment dependent)

---

#### 3. Check Metadata

```bash
clickhouse-client --queries-file 03-metadata-check.sql
```

**What it does**:
- Displays table storage information
- Shows index granularity settings
- Analyzes parts and marks statistics
- Compares index file sizes
- Shows column-level statistics

**Expected time**: < 5 seconds

---

#### 4. Execute Performance Tests

```bash
clickhouse-client --queries-file 04-performance-test.sql
```

**What it does**:
- Single point query tests (WHERE player_id = X)
- Multiple point query tests (WHERE player_id IN (...))
- Small range query tests (WHERE player_id BETWEEN X AND Y)
- EXPLAIN analysis for execution plans

**Expected time**: 10-30 seconds

---

#### 5. Analyze Results

```bash
clickhouse-client --queries-file 05-analyze-results.sql
```

**What it does**:
- Recent query performance summary
- Performance comparison by granularity
- Relative performance analysis
- Query type performance breakdown
- Storage vs performance trade-off analysis
- Recommendations summary

**Expected time**: < 5 seconds

---

#### 6. Cleanup

```bash
clickhouse-client --queries-file 99-cleanup.sql
```

Removes all test data and tables.

### 🔍 Key Concepts

#### What is Index Granularity?

Index granularity determines how many rows are grouped together in each "mark" of the primary index.

| Granularity | Description | Best For |
|-------------|-------------|----------|
| 256 | Smallest marks, most precise | Frequent point queries on specific IDs |
| 1024 | Small marks, good precision | Point queries with good storage efficiency |
| 4096 | Medium marks, balanced | Mixed workload (both point and scan queries) |
| 8192 (default) | Large marks, scan-optimized | Full table scans, aggregation queries |

#### Trade-offs

**Smaller Granularity (256, 1024)**:
- ✅ Faster point queries (fewer rows to scan)
- ✅ More precise index lookups
- ❌ Larger index size
- ❌ More memory for index storage

**Larger Granularity (4096, 8192)**:
- ✅ Smaller index size
- ✅ Better for full table scans
- ✅ Lower memory overhead
- ❌ Slower point queries (more rows to scan per mark)

### 📊 Expected Results

#### Point Query Performance

Typical performance improvements for point queries:

| Granularity | Relative Speed | Rows Read | Index Size |
|-------------|----------------|-----------|------------|
| 256 | ~2-3x faster | ~256 rows | ~4x larger |
| 1024 | ~1.5-2x faster | ~1024 rows | ~2x larger |
| 4096 | ~1.2x faster | ~4096 rows | ~1.2x larger |
| 8192 (baseline) | 1.0x | ~8192 rows | 1.0x (baseline) |

*Actual results may vary based on data distribution and hardware*

#### Storage Comparison

| Metric | G256 | G1024 | G4096 | G8192 |
|--------|------|-------|-------|-------|
| Total Marks | ~7800 | ~1950 | ~488 | ~244 |
| Index Size | Largest | Medium | Small | Smallest |
| Data Size | Same | Same | Same | Same |

### 💡 Performance Tips

#### When to Use Smaller Granularity (256-1024)

- Frequent point queries by primary key
- Low-latency requirements for single-row lookups
- Sufficient memory for larger indexes
- Small to medium table sizes

#### When to Use Larger Granularity (4096-8192)

- Primarily analytical/scan queries
- Large tables (billions of rows)
- Memory-constrained environments
- Mostly aggregation workloads

#### Finding the Right Balance

1. **Start with default (8192)** for new tables
2. **Profile your queries** using query_log
3. **Test with smaller granularity** if you see many point queries
4. **Monitor index memory usage** with system.parts
5. **Measure the impact** before and after changes

### 🔧 Troubleshooting

#### High Memory Usage

```sql
-- Check index memory consumption
SELECT
    table,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS index_memory
FROM system.parts
WHERE database = 'granularity_test'
GROUP BY table;
```

#### Slow Point Queries

```sql
-- Check how many rows are being read
SELECT
    query,
    read_rows,
    query_duration_ms
FROM system.query_log
WHERE query LIKE '%player_id%'
  AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5;
```

#### Verify Granularity Setting

```sql
-- Confirm granularity is applied
SELECT
    name,
    extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity
FROM system.tables
WHERE database = 'granularity_test';
```

### 🎨 Customization

#### Change Data Volume

Edit `02-insert-data.sql` to change the `numbers()` function value:

```sql
-- 10 million rows instead of 2 million
FROM numbers(10000000)
```

#### Test Different IDs

Edit `04-performance-test.sql` to test different player_id values:

```sql
-- Test with different IDs
WHERE player_id IN (10, 100, 1000, 10000, 100000)
```

#### Add More Granularity Values

You can create additional tables with other granularity values like 512, 2048, etc.

### 🛠 Prerequisites

- ClickHouse server (local or cloud)
- ClickHouse client installed
- Basic SQL knowledge
- Sufficient disk space (~200MB for test data)

### 📚 Reference

- [ClickHouse Primary Key and Index Documentation](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- [MergeTree Table Engine Settings](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-creating-a-table)
- [Performance Optimization Guide](https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler)

### 📝 License

MIT License

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2025-12-25

---

## 한국어

ClickHouse의 index_granularity 설정을 비교하고 point query 성능에 미치는 영향을 측정하는 포괄적인 벤치마크 테스트 스위트입니다.

### 🎯 목적

이 랩은 ClickHouse의 다양한 index_granularity 값을 테스트하는 실무 경험을 제공합니다:
- **Granularity 256** - 정확한 point query에 최적화
- **Granularity 1024** - point query에 좋은 균형
- **Granularity 4096** - 균형잡힌 성능
- **Granularity 8192** - 기본 설정, 스캔 쿼리에 최적화

point query 성능을 최적화하거나 워크로드에 적합한 granularity를 선택하려는 경우, 이 랩은 실제 성능 특성을 측정할 수 있는 구조화된 단계별 연습을 제공합니다.

### 📁 파일 구성

```
index-granularity-point-query/
├── README.md                      # 이 파일
├── 01-setup.sql                   # 데이터베이스 및 테이블 생성
├── 02-insert-data.sql             # 200만 rows 테스트 데이터 생성
├── 03-metadata-check.sql          # 메타데이터 및 인덱스 통계
├── 04-performance-test.sql        # Point query 성능 테스트
├── 05-analyze-results.sql         # 성능 분석 및 비교
└── 99-cleanup.sql                 # 정리 스크립트
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd workload/index-granularity-point-query

# 순차 실행
clickhouse-client --queries-file 01-setup.sql
clickhouse-client --queries-file 02-insert-data.sql
clickhouse-client --queries-file 03-metadata-check.sql
clickhouse-client --queries-file 04-performance-test.sql
clickhouse-client --queries-file 05-analyze-results.sql

# 완료 후 정리
clickhouse-client --queries-file 99-cleanup.sql
```

또는 한 번에 실행:

```bash
for file in 01-setup.sql 02-insert-data.sql 03-metadata-check.sql 04-performance-test.sql 05-analyze-results.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 상세 실행 단계

#### 1. 데이터베이스 설정

```bash
clickhouse-client --queries-file 01-setup.sql
```

**수행 작업**:
- `granularity_test` 데이터베이스 생성
- 다양한 granularity 설정을 가진 네 개의 테스트 테이블 생성:
  - `player_g256`: index_granularity = 256
  - `player_g1024`: index_granularity = 1024
  - `player_g4096`: index_granularity = 4096
  - `player_g8192`: index_granularity = 8192 (기본값)

**예상 시간**: 1초 미만

---

#### 2. 테스트 데이터 삽입

```bash
clickhouse-client --queries-file 02-insert-data.sql
```

**수행 작업**:
- 각 테이블에 2,000,000개 rows 삽입
- 다양한 속성을 가진 게임 플레이어 데이터 시뮬레이션
- 모든 granularity 테이블에 데이터 복사

**예상 시간**: 30-60초 (환경에 따라 다름)

---

#### 3. 메타데이터 확인

```bash
clickhouse-client --queries-file 03-metadata-check.sql
```

**수행 작업**:
- 테이블 스토리지 정보 표시
- 인덱스 granularity 설정 표시
- Parts 및 marks 통계 분석
- 인덱스 파일 크기 비교
- 컬럼 레벨 통계 표시

**예상 시간**: 5초 미만

---

#### 4. 성능 테스트 실행

```bash
clickhouse-client --queries-file 04-performance-test.sql
```

**수행 작업**:
- 단일 point query 테스트 (WHERE player_id = X)
- 다중 point query 테스트 (WHERE player_id IN (...))
- 작은 범위 쿼리 테스트 (WHERE player_id BETWEEN X AND Y)
- 실행 계획을 위한 EXPLAIN 분석

**예상 시간**: 10-30초

---

#### 5. 결과 분석

```bash
clickhouse-client --queries-file 05-analyze-results.sql
```

**수행 작업**:
- 최근 쿼리 성능 요약
- Granularity별 성능 비교
- 상대 성능 분석
- 쿼리 타입별 성능 분석
- 스토리지 vs 성능 트레이드오프 분석
- 권장사항 요약

**예상 시간**: 5초 미만

---

#### 6. 정리

```bash
clickhouse-client --queries-file 99-cleanup.sql
```

모든 테스트 데이터와 테이블을 삭제합니다.

### 🔍 핵심 개념

#### Index Granularity란?

Index granularity는 프라이머리 인덱스의 각 "mark"에 얼마나 많은 행이 그룹화되는지를 결정합니다.

| Granularity | 설명 | 최적 용도 |
|-------------|------|-----------|
| 256 | 가장 작은 marks, 가장 정확 | 특정 ID에 대한 빈번한 point query |
| 1024 | 작은 marks, 좋은 정확도 | 좋은 스토리지 효율성을 가진 point query |
| 4096 | 중간 marks, 균형잡힌 | 혼합 워크로드 (point 및 스캔 쿼리 모두) |
| 8192 (기본값) | 큰 marks, 스캔 최적화 | 전체 테이블 스캔, 집계 쿼리 |

#### 트레이드오프

**작은 Granularity (256, 1024)**:
- ✅ 더 빠른 point query (스캔할 행이 적음)
- ✅ 더 정확한 인덱스 조회
- ❌ 더 큰 인덱스 크기
- ❌ 인덱스 저장을 위한 더 많은 메모리

**큰 Granularity (4096, 8192)**:
- ✅ 더 작은 인덱스 크기
- ✅ 전체 테이블 스캔에 더 좋음
- ✅ 더 낮은 메모리 오버헤드
- ❌ 더 느린 point query (mark당 스캔할 행이 많음)

### 📊 예상 결과

#### Point Query 성능

Point query에 대한 일반적인 성능 향상:

| Granularity | 상대 속도 | 읽은 행 수 | 인덱스 크기 |
|-------------|----------|-----------|-----------|
| 256 | ~2-3배 빠름 | ~256 rows | ~4배 큼 |
| 1024 | ~1.5-2배 빠름 | ~1024 rows | ~2배 큼 |
| 4096 | ~1.2배 빠름 | ~4096 rows | ~1.2배 큼 |
| 8192 (기준) | 1.0배 | ~8192 rows | 1.0배 (기준) |

*실제 결과는 데이터 분포 및 하드웨어에 따라 달라질 수 있습니다*

#### 스토리지 비교

| 메트릭 | G256 | G1024 | G4096 | G8192 |
|--------|------|-------|-------|-------|
| 총 Marks | ~7800 | ~1950 | ~488 | ~244 |
| 인덱스 크기 | 가장 큼 | 중간 | 작음 | 가장 작음 |
| 데이터 크기 | 동일 | 동일 | 동일 | 동일 |

### 💡 성능 팁

#### 작은 Granularity (256-1024)를 사용해야 하는 경우

- 프라이머리 키로 빈번한 point query
- 단일 행 조회에 대한 낮은 지연 시간 요구사항
- 더 큰 인덱스를 위한 충분한 메모리
- 작거나 중간 크기의 테이블

#### 큰 Granularity (4096-8192)를 사용해야 하는 경우

- 주로 분석/스캔 쿼리
- 큰 테이블 (수십억 행)
- 메모리 제약이 있는 환경
- 대부분 집계 워크로드

#### 올바른 균형 찾기

1. **새 테이블은 기본값(8192)으로 시작**
2. **query_log를 사용하여 쿼리 프로파일링**
3. **많은 point query가 보이면 작은 granularity로 테스트**
4. **system.parts로 인덱스 메모리 사용량 모니터링**
5. **변경 전후의 영향 측정**

### 🔧 트러블슈팅

#### 높은 메모리 사용량

```sql
-- 인덱스 메모리 소비 확인
SELECT
    table,
    formatReadableSize(sum(primary_key_bytes_in_memory)) AS index_memory
FROM system.parts
WHERE database = 'granularity_test'
GROUP BY table;
```

#### 느린 Point Query

```sql
-- 읽는 행 수 확인
SELECT
    query,
    read_rows,
    query_duration_ms
FROM system.query_log
WHERE query LIKE '%player_id%'
  AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5;
```

#### Granularity 설정 확인

```sql
-- Granularity가 적용되었는지 확인
SELECT
    name,
    extractAllGroupsVertical(create_table_query, 'index_granularity = (\\d+)')[1][1] AS granularity
FROM system.tables
WHERE database = 'granularity_test';
```

### 🎨 커스터마이징

#### 데이터 볼륨 변경

`02-insert-data.sql`에서 `numbers()` 함수 값을 변경:

```sql
-- 200만 대신 1000만 rows
FROM numbers(10000000)
```

#### 다른 ID 테스트

`04-performance-test.sql`에서 다른 player_id 값을 테스트:

```sql
-- 다른 ID로 테스트
WHERE player_id IN (10, 100, 1000, 10000, 100000)
```

#### 더 많은 Granularity 값 추가

512, 2048 등과 같은 다른 granularity 값으로 추가 테이블을 생성할 수 있습니다.

### 🛠 사전 요구사항

- ClickHouse 서버 (로컬 또는 클라우드)
- ClickHouse 클라이언트 설치
- 기본 SQL 지식
- 충분한 디스크 공간 (테스트 데이터용 ~200MB)

### 📚 참고 자료

- [ClickHouse Primary Key and Index Documentation](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- [MergeTree Table Engine Settings](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-creating-a-table)
- [Performance Optimization Guide](https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler)

### 📝 라이선스

MIT License

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2025-12-25
