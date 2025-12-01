# Genome Variants Lab - ClickHouse Hands-on Lab

## 개요 / Overview

이 프로젝트는 ClickHouse를 사용한 유전체 변이 데이터 분석 실습입니다. 30억 건의 변이 데이터를 생성하고, 다양한 쿼리 패턴을 통해 ClickHouse의 성능을 체험합니다.

This project is a hands-on lab for genome variant data analysis using ClickHouse. It generates 3 billion variant records and demonstrates ClickHouse performance through various query patterns.

## 데이터 스키마 / Data Schema

- **106개 컬럼**: 위치 정보, 유전자, 기능적 영향, 집단 빈도, ClinVar, In-silico 예측 점수, Conservation 점수, Splicing 예측, Regulatory 정보 등
- **30억 건**: 실제 유전체 분석 환경을 시뮬레이션
- **파티셔닝**: 염색체별 (24개 파티션: chr1-22, chrX, chrY)

- **106 Columns**: Position info, genes, functional impact, population frequency, ClinVar, in-silico prediction scores, conservation scores, splicing prediction, regulatory info, etc.
- **3 Billion Rows**: Simulates real-world genome analysis environment
- **Partitioning**: By chromosome (24 partitions: chr1-22, chrX, chrY)

## 파일 구조 / File Structure

```
sql-lab-gnome-variants/
├── 01-genome-schema.sql    # 스키마 정의 / Schema definition
├── 02-genome-load.sql      # 데이터 생성 / Data generation
├── 03-genome-query.sql     # 벤치마크 쿼리 / Benchmark queries
├── 04-genome-monitor.sql   # 모니터링 쿼리 / Monitoring queries
├── 05-genome-drop.sql      # 정리 스크립트 / Cleanup script
└── README.md               # 이 파일 / This file
```

## 실행 순서 / Execution Order

### 1. 스키마 생성 / Create Schema
```sql
-- 01-genome-schema.sql 실행 / Execute 01-genome-schema.sql
-- 데이터베이스, 테이블, 인덱스, Materialized View, Projection 생성
-- Creates database, table, indexes, materialized view, and projection
```

**주요 기능 / Key Features:**
- MergeTree 엔진 with 염색체별 파티셔닝 / MergeTree engine with chromosome partitioning
- Bloom Filter 인덱스 (gene, sample_id, clinvar_significance)
- N-gram 인덱스 (유전자명 부분 검색용 / For partial gene name search)
- Materialized View (유전자별 통계 사전 계산 / Pre-computed gene statistics)
- Projection (샘플별 정렬 최적화 / Sample-based sorting optimization)

### 2. 데이터 로드 / Load Data
```sql
-- 02-genome-load.sql 실행 / Execute 02-genome-load.sql
-- 30억 건의 샘플 데이터 생성 (약 10-30분 소요)
-- Generates 3 billion sample records (takes approx. 10-30 minutes)
```

**예상 데이터 크기 / Expected Data Size:**
- 압축 데이터: ~50-100GB (Compressed)
- 비압축 데이터: ~200-400GB (Uncompressed)
- 압축률: 약 4-8배 / Compression ratio: approx. 4-8x

### 3. 쿼리 실행 / Run Queries
```sql
-- 03-genome-query.sql 실행 / Execute 03-genome-query.sql
-- 10개의 벤치마크 쿼리 실행
-- Run 10 benchmark queries
```

**쿼리 패턴 / Query Patterns:**
- **Q1**: Range Query (위치 기반 검색 / Position-based search)
- **Q2**: Gene Filtering (유전자 필터링 / Gene filtering)
- **Q3**: N-gram Search (부분 문자열 검색 / Partial string search)
- **Q4**: Aggregation (유전자별 통계 / Gene-level statistics)
- **Q5**: Complex Query (복합 조건 / Multiple conditions)
- **Q6**: Sample-specific Lookup (샘플별 변이 검색 / Sample-specific variant lookup)
- **Q7**: Chromosome-wide Statistics (염색체별 통계 / Chromosome-wide statistics)
- **Q8**: Clinical Hotspot Analysis (임상 핫스팟 분석 / Clinical hotspot analysis)
- **Q9**: Population Frequency (집단 빈도 분포 / Population frequency distribution)
- **Q10**: Co-occurrence Analysis (공존 패턴 분석 / Co-occurrence pattern analysis)

### 4. 모니터링 / Monitoring
```sql
-- 04-genome-monitor.sql 실행 / Execute 04-genome-monitor.sql
-- 쿼리 성능 및 Granule 스킵 효율 확인
-- Check query performance and granule skip efficiency
```

### 5. 정리 / Cleanup
```sql
-- 05-genome-drop.sql 실행 / Execute 05-genome-drop.sql
-- 모든 데이터 및 데이터베이스 삭제
-- Drop all data and database
```

## 성능 최적화 포인트 / Performance Optimization Points

### 1. Partitioning (파티셔닝)
- 염색체별 파티셔닝으로 쿼리 성능 향상
- Improves query performance with chromosome-based partitioning

### 2. Skip Indices (스킵 인덱스)
- Bloom Filter: 정확한 값 검색 / Exact value search
- N-gram: 부분 문자열 검색 / Partial string search
- Granule 단위 스킵으로 I/O 감소 / Reduces I/O by skipping granules

### 3. Materialized View (구체화 뷰)
- 유전자별 통계를 사전 계산하여 집계 쿼리 가속화
- Accelerates aggregate queries with pre-computed gene statistics

### 4. Projection (프로젝션)
- 샘플별 정렬을 사전 계산하여 샘플 기반 쿼리 최적화
- Optimizes sample-based queries with pre-computed sorting

### 5. LowCardinality 타입
- 카디널리티가 낮은 컬럼에 적용하여 압축률 향상
- Improves compression for low-cardinality columns

## 주요 학습 포인트 / Key Learning Points

1. **대용량 데이터 처리**: 30억 건 데이터 생성 및 쿼리
   - **Large-scale Data Processing**: Generate and query 3 billion records

2. **인덱스 전략**: Bloom Filter, N-gram 인덱스의 효과
   - **Index Strategy**: Effectiveness of Bloom Filter and N-gram indexes

3. **쿼리 최적화**: EXPLAIN을 통한 실행 계획 분석
   - **Query Optimization**: Analyze execution plans with EXPLAIN

4. **성능 모니터링**: query_log를 활용한 성능 분석
   - **Performance Monitoring**: Performance analysis using query_log

5. **Real-world Use Case**: 유전체 변이 분석 시나리오
   - **Real-world Use Case**: Genome variant analysis scenarios

## 시스템 요구사항 / System Requirements

- **ClickHouse**: 23.x 이상 / 23.x or higher
- **메모리**: 최소 16GB 권장 / Minimum 16GB recommended
- **디스크**: 최소 200GB 여유 공간 / Minimum 200GB free space
- **환경**: ClickHouse Cloud 또는 Self-hosted / ClickHouse Cloud or Self-hosted

## 참고사항 / Notes

- 데이터 생성 시간은 시스템 사양에 따라 다를 수 있습니다
  - Data generation time may vary depending on system specifications
- 실제 프로덕션 환경에서는 데이터 백업 및 복구 전략을 수립하세요
  - Establish data backup and recovery strategy for production environments
- 쿼리 성능은 하드웨어, 네트워크, 동시 사용자 수에 영향을 받습니다
  - Query performance is affected by hardware, network, and concurrent users

## 라이선스 / License

이 프로젝트는 교육 및 실습 목적으로 제공됩니다.

This project is provided for educational and hands-on lab purposes.

## 문의 / Contact

질문이나 피드백은 이슈를 통해 남겨주세요.

Please leave questions or feedback through issues.
