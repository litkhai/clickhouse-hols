# Genome Variants Lab - ClickHouse Hands-on Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for genome variant data analysis using ClickHouse, featuring 3 billion variant records and real-world genomics workload patterns.

### 🎯 Purpose

This lab provides practical experience with ClickHouse for genomics data analysis:
- Large-scale genomics data processing (3 billion records)
- Understanding partition strategies for chromosome-based data
- Implementing and testing various indexing techniques
- Optimizing queries for genomics research workflows
- Performance monitoring and tuning for scientific workloads

Whether you're working in bioinformatics or exploring large-scale analytical databases, this lab demonstrates real-world performance characteristics with production-like data volumes.

### 📊 Data Schema

**106 Columns Including**:
- Position information (chromosome, position, reference, alternate)
- Gene and functional impact annotations
- Population frequency data
- ClinVar clinical significance
- In-silico prediction scores
- Conservation scores
- Splicing predictions
- Regulatory information

**Dataset Characteristics**:
- **3 Billion Rows**: Simulates real-world genome analysis environment
- **Partitioning**: By chromosome (24 partitions: chr1-22, chrX, chrY)
- **Compressed Size**: ~50-100GB
- **Uncompressed Size**: ~200-400GB
- **Compression Ratio**: 4-8x

### 📁 File Structure

```
gnome-variants/
├── README.md                # This file
├── 01-genome-schema.sql     # Schema definition
├── 02-genome-load.sql       # Data generation
├── 03-genome-query.sql      # Benchmark queries
├── 04-genome-monitor.sql    # Monitoring queries
└── 05-genome-drop.sql       # Cleanup script
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd usecase/gnome-variants

# 1. Create schema
clickhouse-client < 01-genome-schema.sql

# 2. Load data (takes 10-30 minutes)
clickhouse-client < 02-genome-load.sql

# 3. Run benchmark queries
clickhouse-client < 03-genome-query.sql

# 4. Monitor performance
clickhouse-client < 04-genome-monitor.sql

# 5. Cleanup when done
clickhouse-client < 05-genome-drop.sql
```

### 📖 Detailed Lab Steps

#### 1. Create Schema

```bash
clickhouse-client < 01-genome-schema.sql
```

**What it does**:
- Creates database and table with MergeTree engine
- Sets up chromosome-based partitioning
- Creates skip indices:
  - **Bloom Filter**: For exact value searches (gene, sample_id, clinvar_significance)
  - **N-gram Index**: For partial gene name searches
- Creates Materialized View for pre-computed gene statistics
- Creates Projection for sample-based query optimization

**Expected time**: < 5 seconds

---

#### 2. Load Data

```bash
clickhouse-client < 02-genome-load.sql
```

**What it does**:
- Generates 3 billion sample variant records
- Distributes data across 24 chromosome partitions
- Creates realistic genomics data patterns

**Expected time**: 10-30 minutes (system dependent)

**Expected data size**:
- Compressed: ~50-100GB
- Uncompressed: ~200-400GB
- Compression ratio: 4-8x

**Note**: Ensure sufficient disk space before starting.

---

#### 3. Run Benchmark Queries

```bash
clickhouse-client < 03-genome-query.sql
```

**Query patterns tested**:
- **Q1: Range Query** - Position-based variant search
- **Q2: Gene Filtering** - Filter variants by specific genes
- **Q3: N-gram Search** - Partial gene name matching
- **Q4: Aggregation** - Gene-level statistics computation
- **Q5: Complex Query** - Multiple filtering conditions
- **Q6: Sample-specific Lookup** - Variants for specific samples
- **Q7: Chromosome-wide Statistics** - Chromosome-level aggregations
- **Q8: Clinical Hotspot Analysis** - Pathogenic variant clusters
- **Q9: Population Frequency** - Allele frequency distributions
- **Q10: Co-occurrence Analysis** - Variant co-occurrence patterns

**Expected time**: Varies by query (< 1 second to several seconds)

---

#### 4. Monitor Performance

```bash
clickhouse-client < 04-genome-monitor.sql
```

**What it monitors**:
- Query execution times and resource usage
- Granule skip efficiency (how many granules were skipped)
- Index usage and effectiveness
- Memory and I/O statistics

---

#### 5. Cleanup

```bash
clickhouse-client < 05-genome-drop.sql
```

Removes all data and database.

### 🔍 Performance Optimization Techniques

#### 1. Partitioning
- **Chromosome-based partitioning** improves query performance by pruning irrelevant partitions
- Queries targeting specific chromosomes only read relevant data

#### 2. Skip Indices
- **Bloom Filter**: Efficiently filters exact value matches
- **N-gram**: Enables partial string matching for gene names
- **Granule-level skipping**: Reduces I/O by skipping irrelevant data blocks

#### 3. Materialized View
- **Pre-computed gene statistics** accelerate aggregation queries
- Automatically maintained as new data arrives

#### 4. Projection
- **Sample-based sorting** optimizes sample-specific queries
- Alternative data organization within the same table

#### 5. LowCardinality Type
- **Compression optimization** for columns with low cardinality
- Reduces storage and improves query performance

### 📚 Key Learning Points

1. **Large-scale Data Processing**
   - Generate and query 3 billion records
   - Understand compression and storage characteristics

2. **Index Strategy**
   - When to use Bloom Filter vs N-gram indices
   - Measuring index effectiveness with granule skip rates

3. **Query Optimization**
   - Analyzing execution plans with EXPLAIN
   - Understanding partition pruning
   - Leveraging projections for query acceleration

4. **Performance Monitoring**
   - Using query_log for performance analysis
   - Tracking resource usage and bottlenecks
   - Identifying optimization opportunities

5. **Real-world Use Case**
   - Genomics variant analysis workflows
   - Scientific data processing patterns
   - Production-scale data volumes

### 🛠 Prerequisites

- **ClickHouse**: Version 23.x or higher
- **Memory**: Minimum 16GB recommended, 32GB+ for better performance
- **Disk**: Minimum 200GB free space
- **Environment**: ClickHouse Cloud or Self-hosted

### 🔧 Troubleshooting

#### Data Generation Taking Too Long
- Check system resources (CPU, memory, disk I/O)
- Consider reducing data volume for testing
- Ensure no other heavy workloads are running

#### Out of Memory During Queries
```sql
SET max_memory_usage = 20000000000; -- 20GB
```

#### Query Performance Issues
- Check if indices are being used (run `04-genome-monitor.sql`)
- Verify partition pruning is working (use EXPLAIN)
- Ensure sufficient system resources

### 💡 Performance Tips

- **For Range Queries**: Ensure partition key is used in WHERE clause
- **For Gene Searches**: Utilize Bloom Filter index with exact matches
- **For Partial Searches**: Use N-gram index for gene name patterns
- **For Aggregations**: Consider using pre-computed Materialized Views
- **For Sample Queries**: Leverage sample_id Projection

### 📚 Reference

- [ClickHouse MergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- [Skip Indices Guide](https://clickhouse.com/docs/en/optimize/skipping-indexes)
- [Projections Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#projections)

### 📝 License

This project is provided for educational and hands-on lab purposes.

### 👤 Author

Ken (ClickHouse Solution Architect)

---

## 한국어

ClickHouse를 사용한 유전체 변이 데이터 분석 실습으로, 30억 건의 변이 데이터와 실제 유전체학 워크로드 패턴을 제공합니다.

### 🎯 목적

이 랩은 ClickHouse를 활용한 유전체 데이터 분석에 대한 실무 경험을 제공합니다:
- 대규모 유전체 데이터 처리 (30억 레코드)
- 염색체 기반 데이터를 위한 파티션 전략 이해
- 다양한 인덱싱 기법 구현 및 테스트
- 유전체학 연구 워크플로우를 위한 쿼리 최적화
- 과학 워크로드를 위한 성능 모니터링 및 튜닝

생물정보학 분야에서 일하거나 대규모 분석 데이터베이스를 탐구하는 경우, 이 랩은 프로덕션 수준의 데이터 볼륨으로 실제 성능 특성을 시연합니다.

### 📊 데이터 스키마

**106개 컬럼 포함**:
- 위치 정보 (염색체, 위치, 참조, 대체)
- 유전자 및 기능적 영향 주석
- 집단 빈도 데이터
- ClinVar 임상적 중요성
- In-silico 예측 점수
- Conservation 점수
- Splicing 예측
- Regulatory 정보

**데이터셋 특성**:
- **30억 Rows**: 실제 유전체 분석 환경 시뮬레이션
- **파티셔닝**: 염색체별 (24개 파티션: chr1-22, chrX, chrY)
- **압축 크기**: ~50-100GB
- **비압축 크기**: ~200-400GB
- **압축률**: 4-8배

### 📁 파일 구성

```
gnome-variants/
├── README.md                # 이 파일
├── 01-genome-schema.sql     # 스키마 정의
├── 02-genome-load.sql       # 데이터 생성
├── 03-genome-query.sql      # 벤치마크 쿼리
├── 04-genome-monitor.sql    # 모니터링 쿼리
└── 05-genome-drop.sql       # 정리 스크립트
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd usecase/gnome-variants

# 1. 스키마 생성
clickhouse-client < 01-genome-schema.sql

# 2. 데이터 로드 (10-30분 소요)
clickhouse-client < 02-genome-load.sql

# 3. 벤치마크 쿼리 실행
clickhouse-client < 03-genome-query.sql

# 4. 성능 모니터링
clickhouse-client < 04-genome-monitor.sql

# 5. 완료 후 정리
clickhouse-client < 05-genome-drop.sql
```

### 📖 상세 실습 단계

#### 1. 스키마 생성

```bash
clickhouse-client < 01-genome-schema.sql
```

**수행 작업**:
- MergeTree 엔진으로 데이터베이스 및 테이블 생성
- 염색체 기반 파티셔닝 설정
- Skip 인덱스 생성:
  - **Bloom Filter**: 정확한 값 검색용 (gene, sample_id, clinvar_significance)
  - **N-gram Index**: 유전자명 부분 검색용
- 유전자별 통계를 위한 Materialized View 생성
- 샘플 기반 쿼리 최적화를 위한 Projection 생성

**예상 시간**: 5초 미만

---

#### 2. 데이터 로드

```bash
clickhouse-client < 02-genome-load.sql
```

**수행 작업**:
- 30억 개의 샘플 변이 레코드 생성
- 24개 염색체 파티션에 데이터 분산
- 실제 유전체학 데이터 패턴 생성

**예상 시간**: 10-30분 (시스템 사양에 따라 다름)

**예상 데이터 크기**:
- 압축: ~50-100GB
- 비압축: ~200-400GB
- 압축률: 4-8배

**참고**: 시작하기 전에 충분한 디스크 공간을 확보하세요.

---

#### 3. 벤치마크 쿼리 실행

```bash
clickhouse-client < 03-genome-query.sql
```

**테스트되는 쿼리 패턴**:
- **Q1: Range Query** - 위치 기반 변이 검색
- **Q2: Gene Filtering** - 특정 유전자별 변이 필터링
- **Q3: N-gram Search** - 유전자명 부분 매칭
- **Q4: Aggregation** - 유전자 수준 통계 계산
- **Q5: Complex Query** - 다중 필터링 조건
- **Q6: Sample-specific Lookup** - 특정 샘플의 변이
- **Q7: Chromosome-wide Statistics** - 염색체 수준 집계
- **Q8: Clinical Hotspot Analysis** - 병원성 변이 클러스터
- **Q9: Population Frequency** - 대립 유전자 빈도 분포
- **Q10: Co-occurrence Analysis** - 변이 공존 패턴

**예상 시간**: 쿼리에 따라 다름 (1초 미만부터 수 초)

---

#### 4. 성능 모니터링

```bash
clickhouse-client < 04-genome-monitor.sql
```

**모니터링 내용**:
- 쿼리 실행 시간 및 리소스 사용량
- Granule 스킵 효율성 (스킵된 granule 수)
- 인덱스 사용 및 효과성
- 메모리 및 I/O 통계

---

#### 5. 정리

```bash
clickhouse-client < 05-genome-drop.sql
```

모든 데이터 및 데이터베이스를 삭제합니다.

### 🔍 성능 최적화 기법

#### 1. 파티셔닝
- **염색체 기반 파티셔닝**으로 관련 없는 파티션을 제거하여 쿼리 성능 향상
- 특정 염색체를 대상으로 하는 쿼리는 관련 데이터만 읽음

#### 2. Skip 인덱스
- **Bloom Filter**: 정확한 값 매칭을 효율적으로 필터링
- **N-gram**: 유전자명에 대한 부분 문자열 매칭 지원
- **Granule 수준 스킵**: 관련 없는 데이터 블록을 스킵하여 I/O 감소

#### 3. Materialized View
- **사전 계산된 유전자 통계**로 집계 쿼리 가속화
- 새 데이터가 도착하면 자동으로 유지 관리

#### 4. Projection
- **샘플 기반 정렬**로 샘플별 쿼리 최적화
- 동일한 테이블 내에서 대안적인 데이터 구성

#### 5. LowCardinality 타입
- **낮은 카디널리티 컬럼에 대한 압축 최적화**
- 저장 공간 감소 및 쿼리 성능 향상

### 📚 주요 학습 포인트

1. **대용량 데이터 처리**
   - 30억 레코드 생성 및 쿼리
   - 압축 및 저장 특성 이해

2. **인덱스 전략**
   - Bloom Filter vs N-gram 인덱스 사용 시기
   - Granule 스킵률로 인덱스 효과성 측정

3. **쿼리 최적화**
   - EXPLAIN으로 실행 계획 분석
   - 파티션 프루닝 이해
   - Projection을 활용한 쿼리 가속화

4. **성능 모니터링**
   - query_log를 사용한 성능 분석
   - 리소스 사용 및 병목 현상 추적
   - 최적화 기회 식별

5. **실제 사용 사례**
   - 유전체학 변이 분석 워크플로우
   - 과학 데이터 처리 패턴
   - 프로덕션 규모 데이터 볼륨

### 🛠 사전 요구사항

- **ClickHouse**: 버전 23.x 이상
- **메모리**: 최소 16GB 권장, 32GB+ 권장 (더 나은 성능)
- **디스크**: 최소 200GB 여유 공간
- **환경**: ClickHouse Cloud 또는 Self-hosted

### 🔧 트러블슈팅

#### 데이터 생성이 너무 오래 걸림
- 시스템 리소스 확인 (CPU, 메모리, 디스크 I/O)
- 테스트를 위해 데이터 볼륨 줄이기 고려
- 다른 무거운 워크로드가 실행 중이지 않은지 확인

#### 쿼리 중 메모리 부족
```sql
SET max_memory_usage = 20000000000; -- 20GB
```

#### 쿼리 성능 문제
- 인덱스가 사용되고 있는지 확인 (`04-genome-monitor.sql` 실행)
- 파티션 프루닝이 작동하는지 확인 (EXPLAIN 사용)
- 충분한 시스템 리소스 확보

### 💡 성능 팁

- **Range 쿼리**: WHERE 절에서 파티션 키 사용 확인
- **유전자 검색**: 정확한 매칭에 Bloom Filter 인덱스 활용
- **부분 검색**: 유전자명 패턴에 N-gram 인덱스 사용
- **집계**: 사전 계산된 Materialized View 사용 고려
- **샘플 쿼리**: sample_id Projection 활용

### 📚 참고 자료

- [ClickHouse MergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- [Skip Indices Guide](https://clickhouse.com/docs/en/optimize/skipping-indexes)
- [Projections Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#projections)

### 📝 라이선스

이 프로젝트는 교육 및 실습 목적으로 제공됩니다.

### 👤 작성자

Ken (ClickHouse Solution Architect)
