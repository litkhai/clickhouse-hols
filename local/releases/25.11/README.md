# ClickHouse 25.11 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.11 new features. This directory focuses on verified and working features newly added in ClickHouse 25.11.

### 📋 Overview

ClickHouse 25.11 includes important SQL compatibility improvements, Map type enhancements, spatial data support, and query convenience features.

### 🎯 Key Features

1. **HAVING without GROUP BY** - ANSI SQL compatibility for aggregate filtering
2. **Fractional LIMIT** - Percentage-based data sampling
3. **Map Aggregation (sumMap)** - Direct aggregation on Map types
4. **Geometry Functions (readWKT*)** - WKT format spatial data support

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.11
cd local/25.11
./00-setup.sh

# 2. Run tests for each feature
./01-having-without-groupby.sh
./02-fractional-limit.sh
./03-map-aggregation.sh
./04-geometry-functions.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-mac-setup
./client.sh 2511

# Execute SQL file
cd ../25.11
source 01-having-without-groupby.sql
```

### 📚 Feature Details

#### 1. HAVING without GROUP BY (01-having-without-groupby)

**New Feature:** HAVING clause can now be used without GROUP BY for ANSI SQL compatibility

**Test Content:**
- Traditional HAVING with GROUP BY vs new HAVING without GROUP BY
- Aggregate validation (sum, avg, count)
- Multiple condition filtering
- Data quality checks
- PostgreSQL compatibility scenarios

**Execute:**
```bash
./01-having-without-groupby.sh
# Or
cat 01-having-without-groupby.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- Simplified syntax for aggregate filtering
- `HAVING sum(amount) > 1000` without GROUP BY
- Better PostgreSQL migration support
- Data quality validation patterns
- Business rule validation

**Use Cases:**
- Data quality validation
- Aggregate threshold checks
- Business rule validation
- PostgreSQL query migration
- ETL pipeline quality gates

---

#### 2. Fractional LIMIT (02-fractional-limit)

**New Feature:** LIMIT clause now accepts fractional values (0.0-1.0) for percentage-based sampling

**Test Content:**
- Basic fractional LIMIT syntax (0.1 = 10%, 0.25 = 25%, etc.)
- Data sampling for analysis
- ML training/test data split
- A/B testing group creation
- Performance comparison (full vs sampled)

**Execute:**
```bash
./02-fractional-limit.sh
```

**Key Learning Points:**
- `LIMIT 0.1`: Returns 10% of rows
- `LIMIT 0.25`: Returns 25% of rows
- `LIMIT 0.5`: Returns 50% of rows
- Intuitive percentage-based sampling
- Useful for exploratory data analysis
- ML data splitting made easy

**Use Cases:**
- Exploratory data analysis on large datasets
- Quick statistical sampling
- Machine learning train/test split
- A/B testing group creation
- Data quality checks on samples
- Performance testing with representative data
- Ad-hoc analysis without full scan

---

#### 3. Map Aggregation with sumMap (03-map-aggregation)

**New Feature:** `sumMap()` aggregate function enables direct aggregation on Map types

**Test Content:**
- sumMap aggregation on Map columns
- E-commerce analytics with dynamic dimensions
- Inventory tracking with Map operations
- mapSubtract for calculating net changes
- Semi-structured data analysis patterns

**Execute:**
```bash
./03-map-aggregation.sh
```

**Key Learning Points:**
- `sumMap(map_column)` aggregates values by key
- Clean syntax for semi-structured data
- Supports `mapAdd`, `mapSubtract` for Map operations
- Better performance than manual key extraction
- Ideal for dynamic schemas and flexible data models

**Use Cases:**
- E-commerce analytics with dynamic dimensions
- IoT sensor data aggregation
- User behavior tracking with flexible metrics
- Multi-dimensional business intelligence
- Product analytics with varying attributes
- Financial data with dynamic categories

---

#### 4. Geometry Functions (04-geometry-functions)

**New Feature:** WKT (Well-Known Text) reading functions for spatial data: `readWKTPoint`, `readWKTPolygon`, etc.

**Test Content:**
- Parse WKT format spatial data with readWKTPoint
- Distance calculations using geoDistance
- Points of Interest (POI) proximity queries
- Geohash encoding for spatial indexing
- Location-based services patterns

**Execute:**
```bash
./04-geometry-functions.sh
```

**Key Learning Points:**
- `readWKTPoint('POINT(lon lat)')` parses WKT points
- `geoDistance(lon1, lat1, lon2, lat2)` calculates distances
- `geohashEncode(lon, lat, precision)` for spatial indexing
- Tuple types for efficient coordinate storage
- Integration with spatial analysis functions

**Use Cases:**
- GIS and mapping applications
- Location-based services and POI search
- Spatial data analysis and proximity queries
- Urban planning and zone management
- Logistics and route optimization
- Real estate and property management

---

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:2511/play
- **HTTP API**: http://localhost:2511
- **TCP**: localhost:25111
- **User**: default (no password)

#### Useful Commands

```bash
# Check ClickHouse status
cd ../../oss-mac-setup
./status.sh

# Connect to CLI
./client.sh 2511

# View logs
docker logs clickhouse-25-11

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.11/
├── README.md                       # This document
├── 00-setup.sh                     # ClickHouse 25.11 installation script
├── 01-having-without-groupby.sh    # HAVING without GROUP BY test execution
├── 01-having-without-groupby.sql   # HAVING without GROUP BY SQL
├── 02-fractional-limit.sh          # Fractional LIMIT test execution
├── 02-fractional-limit.sql         # Fractional LIMIT SQL
├── 03-map-aggregation.sh           # Map Aggregation test execution
├── 03-map-aggregation.sql          # Map Aggregation SQL
├── 04-geometry-functions.sh        # Geometry Functions test execution
└── 04-geometry-functions.sql       # Geometry Functions SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **02-fractional-limit** - Start with intuitive sampling syntax
3. **01-having-without-groupby** - Learn SQL compatibility improvements

#### For Intermediate Users
1. **03-map-aggregation** - Semi-structured data with Map types
2. **04-geometry-functions** - Spatial data and GIS concepts
3. Combine features for real-world scenarios

#### For Advanced Users
- Apply these features to production workloads
- Analyze query execution plans with EXPLAIN
- Performance benchmarking and comparison
- Integrate with external GIS tools and systems

### 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.11 Release](https://clickhouse.com/blog/clickhouse-release-25-11)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **Map Functions**: [Map Functions Reference](https://clickhouse.com/docs/en/sql-reference/functions/tuple-map-functions)
- **Geo Functions**: [Geo Functions Reference](https://clickhouse.com/docs/en/sql-reference/functions/geo)

### 📝 Notes

- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default for inspection
- All features have been verified on ClickHouse 25.11.2

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

ClickHouse 25.11 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.11에서 검증된 작동하는 기능에 집중합니다.

### 📋 개요

ClickHouse 25.11은 SQL 호환성 개선, Map 타입 향상, 공간 데이터 지원, 쿼리 편의성 기능을 포함합니다.

### 🎯 주요 기능

1. **HAVING without GROUP BY** - 집계 필터링을 위한 ANSI SQL 호환성
2. **Fractional LIMIT** - 퍼센트 기반 데이터 샘플링
3. **Map Aggregation (sumMap)** - Map 타입 직접 집계
4. **Geometry Functions (readWKT*)** - WKT 형식 공간 데이터 지원

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 25.11 설치 및 시작
cd local/25.11
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-having-without-groupby.sh
./02-fractional-limit.sh
./03-map-aggregation.sh
./04-geometry-functions.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-mac-setup
./client.sh 2511

# SQL 파일 실행
cd ../25.11
source 01-having-without-groupby.sql
```

### 📚 기능 상세

#### 1. HAVING without GROUP BY (01-having-without-groupby)

**새로운 기능:** HAVING 절을 GROUP BY 없이 사용 가능 (ANSI SQL 호환성)

**테스트 내용:**
- 기존 HAVING with GROUP BY vs 새로운 HAVING without GROUP BY
- 집계 검증 (sum, avg, count)
- 다중 조건 필터링
- 데이터 품질 검사
- PostgreSQL 호환성 시나리오

**실행:**
```bash
./01-having-without-groupby.sh
# 또는
cat 01-having-without-groupby.sql | docker exec -i clickhouse-25-11 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- 집계 필터링을 위한 간소화된 문법
- `HAVING sum(amount) > 1000` (GROUP BY 없이)
- 향상된 PostgreSQL 마이그레이션 지원
- 데이터 품질 검증 패턴
- 비즈니스 규칙 검증

**사용 사례:**
- 데이터 품질 검증
- 집계 임계값 검사
- 비즈니스 규칙 검증
- PostgreSQL 쿼리 마이그레이션
- ETL 파이프라인 품질 게이트

---

#### 2. Fractional LIMIT (02-fractional-limit)

**새로운 기능:** LIMIT 절이 퍼센트 기반 샘플링을 위한 소수값(0.0-1.0) 지원

**테스트 내용:**
- 기본 fractional LIMIT 문법 (0.1 = 10%, 0.25 = 25%, 등)
- 분석을 위한 데이터 샘플링
- ML 훈련/테스트 데이터 분할
- A/B 테스트 그룹 생성
- 성능 비교 (전체 vs 샘플)

**실행:**
```bash
./02-fractional-limit.sh
```

**주요 학습 포인트:**
- `LIMIT 0.1`: 10%의 행 반환
- `LIMIT 0.25`: 25%의 행 반환
- `LIMIT 0.5`: 50%의 행 반환
- 직관적인 퍼센트 기반 샘플링
- 탐색적 데이터 분석에 유용
- 간편한 ML 데이터 분할

**사용 사례:**
- 대용량 데이터셋의 탐색적 데이터 분석
- 빠른 통계적 샘플링
- 머신러닝 훈련/테스트 분할
- A/B 테스트 그룹 생성
- 샘플 기반 데이터 품질 검사
- 대표 데이터를 사용한 성능 테스트
- 전체 스캔 없는 임시 분석

---

#### 3. Map Aggregation with sumMap (03-map-aggregation)

**새로운 기능:** `sumMap()` 집계 함수로 Map 타입 직접 집계 가능

**테스트 내용:**
- Map 컬럼에 대한 sumMap 집계
- 동적 차원을 가진 전자상거래 분석
- Map 연산을 사용한 재고 추적
- mapSubtract로 순변화량 계산
- 반정형 데이터 분석 패턴

**실행:**
```bash
./03-map-aggregation.sh
```

**주요 학습 포인트:**
- `sumMap(map_column)`로 키별 값 집계
- 반정형 데이터를 위한 깔끔한 문법
- `mapAdd`, `mapSubtract` 등 Map 연산 지원
- 수동 키 추출보다 나은 성능
- 동적 스키마와 유연한 데이터 모델에 이상적

**사용 사례:**
- 동적 차원을 가진 전자상거래 분석
- IoT 센서 데이터 집계
- 유연한 메트릭을 가진 사용자 행동 추적
- 다차원 비즈니스 인텔리전스
- 다양한 속성을 가진 제품 분석
- 동적 카테고리를 가진 금융 데이터

---

#### 4. Geometry Functions (04-geometry-functions)

**새로운 기능:** 공간 데이터를 위한 WKT(Well-Known Text) 읽기 함수: `readWKTPoint`, `readWKTPolygon` 등

**테스트 내용:**
- readWKTPoint로 WKT 형식 공간 데이터 파싱
- geoDistance를 사용한 거리 계산
- POI(관심 지점) 근접 쿼리
- 공간 인덱싱을 위한 Geohash 인코딩
- 위치 기반 서비스 패턴

**실행:**
```bash
./04-geometry-functions.sh
```

**주요 학습 포인트:**
- `readWKTPoint('POINT(lon lat)')`로 WKT 포인트 파싱
- `geoDistance(lon1, lat1, lon2, lat2)`로 거리 계산
- `geohashEncode(lon, lat, precision)`로 공간 인덱싱
- 효율적인 좌표 저장을 위한 Tuple 타입
- 공간 분석 함수와의 통합

**사용 사례:**
- GIS 및 매핑 애플리케이션
- 위치 기반 서비스 및 POI 검색
- 공간 데이터 분석 및 근접 쿼리
- 도시 계획 및 구역 관리
- 물류 및 경로 최적화
- 부동산 및 자산 관리

---

### 🔧 관리

#### ClickHouse 접속 정보

- **Web UI**: http://localhost:2511/play
- **HTTP API**: http://localhost:2511
- **TCP**: localhost:25111
- **User**: default (no password)

#### 유용한 명령어

```bash
# ClickHouse 상태 확인
cd ../../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2511

# 로그 확인
docker logs clickhouse-25-11

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.11/
├── README.md                       # 이 문서
├── 00-setup.sh                     # ClickHouse 25.11 설치 스크립트
├── 01-having-without-groupby.sh    # HAVING without GROUP BY 테스트 실행
├── 01-having-without-groupby.sql   # HAVING without GROUP BY SQL
├── 02-fractional-limit.sh          # Fractional LIMIT 테스트 실행
├── 02-fractional-limit.sql         # Fractional LIMIT SQL
├── 03-map-aggregation.sh           # Map Aggregation 테스트 실행
├── 03-map-aggregation.sql          # Map Aggregation SQL
├── 04-geometry-functions.sh        # Geometry Functions 테스트 실행
└── 04-geometry-functions.sql       # Geometry Functions SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-fractional-limit** - 직관적인 샘플링 문법부터 시작
3. **01-having-without-groupby** - SQL 호환성 개선 학습

#### 중급 사용자
1. **03-map-aggregation** - Map 타입을 사용한 반정형 데이터
2. **04-geometry-functions** - 공간 데이터 및 GIS 개념
3. 실제 시나리오에 기능 결합

#### 고급 사용자
- 프로덕션 워크로드에 이 기능들 적용
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 비교
- 외부 GIS 도구 및 시스템과 통합

### 🔍 추가 자료

- **Official Release Blog**: [ClickHouse 25.11 Release](https://clickhouse.com/blog/clickhouse-release-25-11)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **Map Functions**: [Map Functions Reference](https://clickhouse.com/docs/en/sql-reference/functions/tuple-map-functions)
- **Geo Functions**: [Geo Functions Reference](https://clickhouse.com/docs/en/sql-reference/functions/geo)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 검사할 수 있습니다
- 모든 기능은 ClickHouse 25.11.2에서 검증되었습니다

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
