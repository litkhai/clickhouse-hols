# ClickHouse 25.5 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.5 new features. This directory is designed for practical exercises and iterative learning of features newly added in ClickHouse 25.5.

### 🎯 Overview

ClickHouse 25.5 includes Vector Similarity Index (Beta), Hive Metastore Catalog support, Implicit Table feature, new functions, and enhanced Geo Types in Parquet.

### 🌟 Key Features

1. **Vector Similarity Index (Beta)** - Approximate nearest neighbor search with filtering strategies
2. **Hive Metastore Catalog** - Lakehouse integration for Iceberg tables
3. **Implicit Table in clickhouse-local** - Simplified data exploration without explicit FROM clause
4. **New Functions** - sparseGrams, map functions, iceberg functions
5. **Geo Types in Parquet** - Native parsing of WKB-encoded geometries

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.5
cd local/releases/25.5
./00-setup.sh

# 2. Run tests for each feature
./01-vector-similarity-index.sh
./02-hive-metastore-catalog.sh
./03-implicit-table.sh
./04-new-functions.sh
./05-geo-types-parquet.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-mac-setup
./client.sh 8123

# Execute SQL file
cd ../releases/25.5
source 01-vector-similarity-index.sql
```

### 📚 Feature Details

#### 1. Vector Similarity Index (Beta) (01-vector-similarity-index)

**New Feature:** Vector similarity search graduated to beta with hybrid search capabilities

**Test Content:**
- HNSW vector index creation
- L2Distance similarity search
- Prefiltering strategy (filter first, then search)
- Postfiltering strategy (search first, then filter)
- Hybrid search combining vector similarity with metadata filters
- Product recommendation system use case

**Execute:**
```bash
./01-vector-similarity-index.sh
# Or
cat 01-vector-similarity-index.sql | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- `vector_similarity('hnsw', 'L2Distance')`: HNSW index with L2 distance metric
- Prefiltering: Apply filters first, better for highly selective filters
- Postfiltering: Vector search first, better for broad searches
- `vector_search_filter_strategy` setting: auto, prefilter, postfilter
- Combines semantic search with business logic filters

**Real-World Use Cases:**
- E-commerce product recommendations
- Content discovery and personalization
- Image and document similarity search
- Anomaly detection in embeddings
- Question-answering systems
- Customer segmentation

---

#### 2. Hive Metastore Catalog (02-hive-metastore-catalog)

**New Feature:** Support for Hive metastore catalog to query Iceberg tables

**Test Content:**
- DataLakeCatalog table function usage
- Iceberg table format integration
- Thrift protocol configuration
- Lakehouse query patterns
- Data lake analytics without data movement

**Execute:**
```bash
./02-hive-metastore-catalog.sh
```

**Key Learning Points:**
- `DataLakeCatalog('catalog_type', 'metastore_uri', 'database.table')`
- Extends lakehouse capabilities alongside Unity and AWS Glue
- Query Iceberg tables in-place without ETL
- Integrates with Hive/Spark ecosystems
- Supports partitioned and evolving schemas

**Real-World Use Cases:**
- Analytics on S3 data lakes
- Hybrid queries (warehouse + lake)
- Cost optimization via data tiering
- Data exploration without copying
- Multi-engine analytics (Spark + ClickHouse)
- Historical data analysis

---

#### 3. Implicit Table in clickhouse-local (03-implicit-table)

**New Feature:** Omit FROM and SELECT clauses for quick data exploration

**Test Content:**
- Implicit table with streamed stdin data
- JSONAllPathsWithTypes() for schema discovery
- Simplified data exploration patterns
- Quick inspection of JSON structures
- Log analysis use cases

**Execute:**
```bash
./03-implicit-table.sh
```

**Key Learning Points:**
- Use `_` to reference implicit table in clickhouse-local
- Automatic schema inference from JSON data
- No need for explicit FROM clause
- Perfect for ad-hoc analysis
- Combines with functions like JSONAllPathsWithTypes()

**Real-World Use Cases:**
- Quick JSON schema inspection
- Log file analysis without tables
- Data quality validation
- Rapid prototyping
- Ad-hoc API response analysis
- Production debugging

---

#### 4. New Functions (04-new-functions)

**New Feature:** Eight new functions introduced in ClickHouse 25.5

**Test Content:**
- `sparseGrams(string, n)` - substring extraction for text analysis
- `mapContainsKey(map, key)` - check if map has key
- `mapContainsValue(map, value)` - check if map has value
- `mapContainsValueLike(map, pattern)` - pattern matching in map values
- `icebergHash(value)` - Iceberg-compatible hashing
- `icebergBucketTransform(buckets, value)` - Iceberg bucketing

**Execute:**
```bash
./04-new-functions.sh
```

**Key Learning Points:**
- sparseGrams: Extract all substrings with length >= n
- Map functions: Efficient filtering without extraction
- Iceberg functions: Compatible partitioning with Apache Iceberg
- All functions optimized for performance
- Enables new query patterns

**Real-World Use Cases:**
- Text mining and fuzzy search (sparseGrams)
- Configuration and metadata filtering (map functions)
- Lakehouse integration (Iceberg functions)
- Feature stores with map-based attributes
- Document similarity analysis
- Multi-catalog data management

---

#### 5. Geo Types in Parquet (05-geo-types-parquet)

**New Feature:** Enhanced Parquet reader for geographic data types

**Test Content:**
- WKB-encoded geometry parsing
- Point, LineString, Polygon types
- MultiPoint, MultiLineString, MultiPolygon
- GeoParquet dataset analysis
- Spatial query patterns

**Execute:**
```bash
./05-geo-types-parquet.sh
```

**Key Learning Points:**
- Auto-infers Point, LineString, Polygon from WKB
- No manual binary conversion needed
- Seamless GeoParquet standard integration
- Efficient spatial queries on large datasets
- Direct analysis of geo data lakes

**Real-World Use Cases:**
- Retail store location analysis
- Route planning and logistics
- Real estate market analysis
- Urban planning and zoning
- Traffic pattern analysis
- Climate and environmental monitoring

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### Useful Commands

```bash
# Check ClickHouse status
cd ../../oss-mac-setup
./status.sh

# Connect to CLI
./client.sh 8123

# View logs
docker logs clickhouse-25-5

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.5/
├── README.md                          # This document
├── 00-setup.sh                        # ClickHouse 25.5 installation script
├── 01-vector-similarity-index.sh      # Vector similarity test execution
├── 01-vector-similarity-index.sql     # Vector similarity SQL
├── 02-hive-metastore-catalog.sh       # Hive metastore test execution
├── 02-hive-metastore-catalog.sql      # Hive metastore SQL
├── 03-implicit-table.sh               # Implicit table test execution
├── 03-implicit-table.sql              # Implicit table SQL
├── 04-new-functions.sh                # New functions test execution
├── 04-new-functions.sql               # New functions SQL
├── 05-geo-types-parquet.sh            # Geo types test execution
└── 05-geo-types-parquet.sql           # Geo types SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **04-new-functions** - Start with new function basics
3. **03-implicit-table** - Learn simplified exploration

#### For Intermediate Users
1. **01-vector-similarity-index** - Understand vector search
2. **05-geo-types-parquet** - Spatial data analysis
3. **02-hive-metastore-catalog** - Lakehouse integration

#### For Advanced Users
- Combine all features for real production scenarios
- Design hybrid search systems
- Build lakehouse analytics pipelines
- Integrate with ML workflows

### 💡 Feature Comparison

#### Vector Search Filter Strategies

| Strategy | When to Use | Performance |
|----------|-------------|-------------|
| Prefilter | Highly selective filters (<10%) | Faster with selective filters |
| Postfilter | Broad searches, low selectivity | Faster for large result sets |
| Auto | Let ClickHouse decide | Optimal in most cases |

#### Catalog Type Comparison

| Catalog | Use Case | Protocol |
|---------|----------|----------|
| Hive Metastore | Traditional Hadoop | Thrift |
| AWS Glue | Managed AWS service | AWS SDK |
| Unity Catalog | Databricks governance | REST API |

### 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.5 Release](https://clickhouse.com/blog/clickhouse-release-25-05)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 Notes

- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default
- Some features require external services (Hive metastore)
- Thorough testing recommended before production use

### 🔒 Security Considerations

**Vector Similarity Index:**
- Embeddings may contain sensitive information
- Consider access controls on vector columns
- Monitor query costs for large-scale searches

**Hive Metastore Integration:**
- Ensure secure network connectivity
- Use appropriate S3/HDFS credentials
- Validate data access permissions

**Geo Data:**
- Location data is sensitive
- Comply with privacy regulations
- Implement appropriate anonymization

### ⚡ Performance Tips

**Vector Similarity Index:**
- Choose appropriate GRANULARITY based on data size
- Use prefilter for highly selective queries
- Monitor vector_search_filter_strategy effectiveness
- Consider index build time for large datasets

**Lakehouse Queries:**
- Use partition pruning aggressively
- Cache frequently accessed metadata
- Optimize Iceberg file layouts
- Monitor query performance metrics

**Geo Queries:**
- Pre-filter with bounding boxes
- Partition by geographic regions
- Use appropriate coordinate precision
- Consider spatial indexes when available

### 🤝 Contributing

If you have improvements or additional examples for this lab:
1. Register an issue
2. Submit a Pull Request
3. Share feedback

### 📄 License

MIT License - Free to learn and modify

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse 25.5 신기능을 학습하고 테스트하는 실습 환경입니다. 이 디렉토리는 ClickHouse 25.5에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

### 🎯 개요

ClickHouse 25.5는 Vector Similarity Index (Beta), Hive Metastore Catalog 지원, Implicit Table 기능, 새로운 함수들, 그리고 Parquet의 향상된 Geo Types 지원을 포함합니다.

### 🌟 주요 기능

1. **Vector Similarity Index (Beta)** - 필터링 전략을 갖춘 근사 최근접 이웃 검색
2. **Hive Metastore Catalog** - Iceberg 테이블을 위한 레이크하우스 통합
3. **Implicit Table in clickhouse-local** - 명시적 FROM 절 없이 데이터 탐색
4. **New Functions** - sparseGrams, map 함수들, iceberg 함수들
5. **Geo Types in Parquet** - WKB 인코딩된 지오메트리 네이티브 파싱

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 25.5 설치 및 시작
cd local/releases/25.5
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-vector-similarity-index.sh
./02-hive-metastore-catalog.sh
./03-implicit-table.sh
./04-new-functions.sh
./05-geo-types-parquet.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-mac-setup
./client.sh 8123

# SQL 파일 실행
cd ../releases/25.5
source 01-vector-similarity-index.sql
```

### 📚 기능 상세

#### 1. Vector Similarity Index (Beta) (01-vector-similarity-index)

**새로운 기능:** 하이브리드 검색 기능을 갖춘 벡터 유사도 검색이 베타로 출시

**테스트 내용:**
- HNSW 벡터 인덱스 생성
- L2Distance 유사도 검색
- Prefiltering 전략 (필터 먼저, 그 다음 검색)
- Postfiltering 전략 (검색 먼저, 그 다음 필터)
- 벡터 유사도와 메타데이터 필터를 결합한 하이브리드 검색
- 제품 추천 시스템 사용 사례

**실행:**
```bash
./01-vector-similarity-index.sh
# 또는
cat 01-vector-similarity-index.sql | docker exec -i clickhouse-25-5 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- `vector_similarity('hnsw', 'L2Distance')`: L2 거리 메트릭을 사용하는 HNSW 인덱스
- Prefiltering: 필터를 먼저 적용, 선택성이 높은 필터에 적합
- Postfiltering: 벡터 검색 먼저, 광범위한 검색에 적합
- `vector_search_filter_strategy` 설정: auto, prefilter, postfilter
- 의미론적 검색과 비즈니스 로직 필터 결합

**실무 활용:**
- 전자상거래 제품 추천
- 콘텐츠 발견 및 개인화
- 이미지 및 문서 유사도 검색
- 임베딩 이상 탐지
- 질의응답 시스템
- 고객 세분화

---

#### 2. Hive Metastore Catalog (02-hive-metastore-catalog)

**새로운 기능:** Iceberg 테이블 쿼리를 위한 Hive 메타스토어 카탈로그 지원

**테스트 내용:**
- DataLakeCatalog 테이블 함수 사용법
- Iceberg 테이블 포맷 통합
- Thrift 프로토콜 구성
- 레이크하우스 쿼리 패턴
- 데이터 이동 없는 데이터 레이크 분석

**실행:**
```bash
./02-hive-metastore-catalog.sh
```

**주요 학습 포인트:**
- `DataLakeCatalog('catalog_type', 'metastore_uri', 'database.table')`
- Unity 및 AWS Glue와 함께 레이크하우스 기능 확장
- ETL 없이 Iceberg 테이블을 제자리에서 쿼리
- Hive/Spark 에코시스템과 통합
- 파티션 및 진화하는 스키마 지원

**실무 활용:**
- S3 데이터 레이크 분석
- 하이브리드 쿼리 (웨어하우스 + 레이크)
- 데이터 계층화를 통한 비용 최적화
- 복사 없이 데이터 탐색
- 다중 엔진 분석 (Spark + ClickHouse)
- 히스토리컬 데이터 분석

---

#### 3. Implicit Table in clickhouse-local (03-implicit-table)

**새로운 기능:** 빠른 데이터 탐색을 위해 FROM 및 SELECT 절 생략

**테스트 내용:**
- stdin 스트림 데이터를 사용한 암시적 테이블
- 스키마 발견을 위한 JSONAllPathsWithTypes()
- 간소화된 데이터 탐색 패턴
- JSON 구조의 빠른 검사
- 로그 분석 사용 사례

**실행:**
```bash
./03-implicit-table.sh
```

**주요 학습 포인트:**
- clickhouse-local에서 `_`를 사용하여 암시적 테이블 참조
- JSON 데이터로부터 자동 스키마 추론
- 명시적 FROM 절 불필요
- 임시 분석에 완벽함
- JSONAllPathsWithTypes() 같은 함수와 결합

**실무 활용:**
- 빠른 JSON 스키마 검사
- 테이블 없이 로그 파일 분석
- 데이터 품질 검증
- 빠른 프로토타이핑
- 임시 API 응답 분석
- 프로덕션 디버깅

---

#### 4. New Functions (04-new-functions)

**새로운 기능:** ClickHouse 25.5에 도입된 8개의 새로운 함수

**테스트 내용:**
- `sparseGrams(string, n)` - 텍스트 분석을 위한 부분 문자열 추출
- `mapContainsKey(map, key)` - 맵이 키를 가지고 있는지 확인
- `mapContainsValue(map, value)` - 맵이 값을 가지고 있는지 확인
- `mapContainsValueLike(map, pattern)` - 맵 값에서 패턴 매칭
- `icebergHash(value)` - Iceberg 호환 해싱
- `icebergBucketTransform(buckets, value)` - Iceberg 버킷팅

**실행:**
```bash
./04-new-functions.sh
```

**주요 학습 포인트:**
- sparseGrams: 길이 >= n인 모든 부분 문자열 추출
- Map 함수들: 추출 없이 효율적인 필터링
- Iceberg 함수들: Apache Iceberg와 호환되는 파티셔닝
- 모든 함수가 성능에 최적화됨
- 새로운 쿼리 패턴 가능

**실무 활용:**
- 텍스트 마이닝 및 퍼지 검색 (sparseGrams)
- 구성 및 메타데이터 필터링 (map 함수)
- 레이크하우스 통합 (Iceberg 함수)
- 맵 기반 속성을 가진 피처 스토어
- 문서 유사도 분석
- 다중 카탈로그 데이터 관리

---

#### 5. Geo Types in Parquet (05-geo-types-parquet)

**새로운 기능:** 지리적 데이터 타입을 위한 향상된 Parquet 리더

**테스트 내용:**
- WKB 인코딩된 지오메트리 파싱
- Point, LineString, Polygon 타입
- MultiPoint, MultiLineString, MultiPolygon
- GeoParquet 데이터셋 분석
- 공간 쿼리 패턴

**실행:**
```bash
./05-geo-types-parquet.sh
```

**주요 학습 포인트:**
- WKB로부터 Point, LineString, Polygon 자동 추론
- 수동 바이너리 변환 불필요
- 원활한 GeoParquet 표준 통합
- 대규모 데이터셋에서 효율적인 공간 쿼리
- 지오 데이터 레이크 직접 분석

**실무 활용:**
- 소매 매장 위치 분석
- 경로 계획 및 물류
- 부동산 시장 분석
- 도시 계획 및 구역 설정
- 교통 패턴 분석
- 기후 및 환경 모니터링

### 🔧 관리

#### ClickHouse 접속 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### 유용한 명령어

```bash
# ClickHouse 상태 확인
cd ../../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 8123

# 로그 확인
docker logs clickhouse-25-5

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.5/
├── README.md                          # 이 문서
├── 00-setup.sh                        # ClickHouse 25.5 설치 스크립트
├── 01-vector-similarity-index.sh      # Vector similarity 테스트 실행
├── 01-vector-similarity-index.sql     # Vector similarity SQL
├── 02-hive-metastore-catalog.sh       # Hive metastore 테스트 실행
├── 02-hive-metastore-catalog.sql      # Hive metastore SQL
├── 03-implicit-table.sh               # Implicit table 테스트 실행
├── 03-implicit-table.sql              # Implicit table SQL
├── 04-new-functions.sh                # New functions 테스트 실행
├── 04-new-functions.sql               # New functions SQL
├── 05-geo-types-parquet.sh            # Geo types 테스트 실행
└── 05-geo-types-parquet.sql           # Geo types SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **04-new-functions** - 새로운 함수 기초부터 시작
3. **03-implicit-table** - 간소화된 탐색 학습

#### 중급 사용자
1. **01-vector-similarity-index** - 벡터 검색 이해
2. **05-geo-types-parquet** - 공간 데이터 분석
3. **02-hive-metastore-catalog** - 레이크하우스 통합

#### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- 하이브리드 검색 시스템 설계
- 레이크하우스 분석 파이프라인 구축
- ML 워크플로우와 통합

### 💡 기능 비교

#### 벡터 검색 필터 전략

| 전략 | 사용 시기 | 성능 |
|------|----------|------|
| Prefilter | 선택성이 높은 필터 (<10%) | 선택적 필터에 더 빠름 |
| Postfilter | 광범위한 검색, 낮은 선택성 | 큰 결과 집합에 더 빠름 |
| Auto | ClickHouse가 결정하도록 | 대부분의 경우 최적 |

#### 카탈로그 타입 비교

| 카탈로그 | 사용 사례 | 프로토콜 |
|---------|---------|---------|
| Hive Metastore | 전통적인 Hadoop | Thrift |
| AWS Glue | 관리형 AWS 서비스 | AWS SDK |
| Unity Catalog | Databricks 거버넌스 | REST API |

### 🔍 추가 자료

- **Official Release Blog**: [ClickHouse 25.5 Release](https://clickhouse.com/blog/clickhouse-release-25-05)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 일부 기능은 외부 서비스가 필요합니다 (Hive metastore)
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다

### 🔒 보안 고려사항

**Vector Similarity Index:**
- 임베딩에 민감한 정보가 포함될 수 있음
- 벡터 컬럼에 대한 접근 제어 고려
- 대규모 검색의 쿼리 비용 모니터링

**Hive Metastore 통합:**
- 안전한 네트워크 연결 보장
- 적절한 S3/HDFS 자격 증명 사용
- 데이터 접근 권한 검증

**지오 데이터:**
- 위치 데이터는 민감함
- 개인정보 보호 규정 준수
- 적절한 익명화 구현

### ⚡ 성능 팁

**Vector Similarity Index:**
- 데이터 크기에 따라 적절한 GRANULARITY 선택
- 선택성이 높은 쿼리에는 prefilter 사용
- vector_search_filter_strategy 효과 모니터링
- 대규모 데이터셋의 인덱스 빌드 시간 고려

**레이크하우스 쿼리:**
- 파티션 프루닝 적극 활용
- 자주 접근하는 메타데이터 캐싱
- Iceberg 파일 레이아웃 최적화
- 쿼리 성능 메트릭 모니터링

**지오 쿼리:**
- 바운딩 박스로 사전 필터링
- 지리적 지역별 파티셔닝
- 적절한 좌표 정밀도 사용
- 가능한 경우 공간 인덱스 고려

### 🤝 기여

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

### 📄 라이선스

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🚀**

질문이나 이슈가 있으면 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
