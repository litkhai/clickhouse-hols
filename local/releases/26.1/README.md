# ClickHouse 26.1 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.1 new features. This directory focuses on verified and working features newly added in ClickHouse 26.1, the first release of 2026.

### 📋 Overview

ClickHouse 26.1 includes significant enhancements in data management, text search capabilities, keeper operations, and performance optimizations. This release features new functions, expanded data type support, and improved query execution strategies.

### 🎯 Key Features

1. **reverseBySeparator Function** - New string function for flexible text manipulation
2. **Text Index for Array Columns** - Full-text search capabilities extended to arrays
3. **HTTP API for ClickHouse Keeper** - Built-in web UI and REST API for keeper monitoring
4. **DeltaLake Deletion Vectors** - Efficient row-level deletion support for data lakes

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 26.1
cd local/releases/26.1
./00-setup.sh

# 2. Run tests for each feature
./01-reverse-by-separator.sh
./02-text-index-arrays.sh
./03-keeper-http-api.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-mac-setup
./client.sh 8123

# Execute SQL file
cd ../local/releases/26.1
source 01-reverse-by-separator.sql
```

### 📚 Feature Details

#### 1. reverseBySeparator Function (01-reverse-by-separator)

**New Feature:** Function that reverses the order of substrings in a string separated by a specified separator

**Test Content:**
- Basic string reversal with various separators
- Path manipulation (URL paths, file paths)
- Domain name reversing (e.g., com.example.www)
- CSV column reordering
- Breadcrumb navigation reversal
- Log format transformation

**Execute:**
```bash
./01-reverse-by-separator.sh
# Or
cat 01-reverse-by-separator.sql | docker exec -i clickhouse-26-1 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- `reverseBySeparator(separator, string)` reverses substring order
- Useful for path normalization and format conversion
- Works with any string separator (/, ., -, etc.)
- Preserves empty segments in the string
- Can be combined with other string functions
- Efficient for URL and path manipulation

**Use Cases:**
- URL path manipulation and normalization
- Reverse domain name lookups (PTR records)
- File path transformations
- Log format conversions
- Breadcrumb navigation building
- CSV/TSV column reordering
- Namespace and package name handling
- Hierarchical data restructuring

---

#### 2. Text Index for Array Columns (02-text-index-arrays)

**New Feature:** Text indexing capabilities extended to support Array data types for full-text search

**Test Content:**
- Creating text indexes on Array(String) columns
- Multi-keyword search in arrays
- Tag and category search optimization
- Product feature search
- Comment and review text search
- Performance comparison with and without indexes

**Execute:**
```bash
./02-text-index-arrays.sh
```

**Key Learning Points:**
- Text indexes now work on `Array(String)` columns
- Significantly improves search performance on array data
- Uses same syntax as regular text indexes
- Supports various tokenizers (ngrams, tokens, etc.)
- Can index tags, categories, and multi-value fields
- Reduces query latency for array searches

**Use Cases:**
- Product tag and category search
- Multi-keyword article search
- E-commerce filter optimization
- Social media hashtag search
- Document keyword indexing
- User interest and preference search
- Skills and capabilities matching
- Content recommendation systems

---

#### 3. HTTP API for ClickHouse Keeper (03-keeper-http-api)

**New Feature:** Built-in HTTP API and embedded web interface for ClickHouse Keeper monitoring and management

**Test Content:**
- Accessing Keeper status via HTTP API
- Querying cluster configuration
- Monitoring keeper metrics
- Inspecting znode data
- Health check endpoints
- Web UI exploration

**Execute:**
```bash
./03-keeper-http-api.sh
```

**Key Learning Points:**
- Keeper now includes built-in HTTP API
- Web UI available at keeper's HTTP port
- REST endpoints for status, config, and metrics
- No external tools required for monitoring
- JSON responses for easy integration
- Simplifies keeper operations and debugging

**Use Cases:**
- Keeper health monitoring
- Cluster configuration inspection
- Operational dashboards
- Automated health checks
- Integration with monitoring tools (Prometheus, Grafana)
- Troubleshooting keeper issues
- Znode data inspection
- Cluster status visualization

---

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
docker logs clickhouse-26-1

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
26.1/
├── README.md                        # This document
├── 00-setup.sh                      # ClickHouse 26.1 installation script
├── 01-reverse-by-separator.sh       # reverseBySeparator function test
├── 01-reverse-by-separator.sql      # reverseBySeparator SQL
├── 02-text-index-arrays.sh          # Text index for arrays test
├── 02-text-index-arrays.sql         # Text index for arrays SQL
├── 03-keeper-http-api.sh            # Keeper HTTP API test
└── 03-keeper-http-api.sql           # Keeper HTTP API SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **01-reverse-by-separator** - Learn new string manipulation functions
3. **02-text-index-arrays** - Introduction to full-text search on arrays

#### For Intermediate Users
1. **03-keeper-http-api** - Explore keeper management and monitoring
2. Build search features with text indexes on arrays
3. Integrate string functions into data processing pipelines

#### For Advanced Users
- Apply text indexes to production array columns
- Build keeper monitoring dashboards
- Performance optimization with new features
- Integrate keeper API with external monitoring systems

### 🔍 Additional Resources

- **Release Presentation**: [ClickHouse 26.1 Community Call](https://clickhouse.com/company/events/v26-01-community-release-call)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2026](https://clickhouse.com/docs/whats-new/changelog)
- **Newsletter**: [January 2026 Newsletter](https://clickhouse.com/blog/202601-newsletter)

### 📝 Notes

- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default for inspection
- All features have been verified on ClickHouse 26.1.1

### 🆕 What's New in 26.1

- **New String Functions** including reverseBySeparator for flexible text manipulation
- **Text Index Enhancements** with Array column support
- **Keeper Improvements** with built-in HTTP API and web UI
- **Performance Optimizations** including skip indexes on data read (default enabled)
- **DeltaLake Support** with deletion vectors for efficient row-level operations
- **Enhanced Type System** with Variant type as default common type
- **Query Optimizations** with improved JOIN filter pushdown and window functions

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

ClickHouse 26.1 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 첫 번째 릴리스인 ClickHouse 26.1에서 검증된 작동하는 기능에 집중합니다.

### 📋 개요

ClickHouse 26.1은 데이터 관리, 텍스트 검색 기능, keeper 운영 및 성능 최적화에서 중요한 개선사항을 포함합니다. 이 릴리스는 새로운 함수, 확장된 데이터 타입 지원, 그리고 개선된 쿼리 실행 전략을 제공합니다.

### 🎯 주요 기능

1. **reverseBySeparator Function** - 유연한 텍스트 조작을 위한 새로운 문자열 함수
2. **Text Index for Array Columns** - 배열에 대한 전체 텍스트 검색 기능 확장
3. **HTTP API for ClickHouse Keeper** - keeper 모니터링을 위한 내장 웹 UI 및 REST API
4. **DeltaLake Deletion Vectors** - 데이터 레이크를 위한 효율적인 행 수준 삭제 지원

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 26.1 설치 및 시작
cd local/releases/26.1
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-reverse-by-separator.sh
./02-text-index-arrays.sh
./03-keeper-http-api.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-mac-setup
./client.sh 8123

# SQL 파일 실행
cd ../local/releases/26.1
source 01-reverse-by-separator.sql
```

### 📚 기능 상세

#### 1. reverseBySeparator Function (01-reverse-by-separator)

**새로운 기능:** 지정된 구분자로 분리된 문자열의 하위 문자열 순서를 반전시키는 함수

**테스트 내용:**
- 다양한 구분자를 사용한 기본 문자열 반전
- 경로 조작 (URL 경로, 파일 경로)
- 도메인 이름 반전 (예: com.example.www)
- CSV 컬럼 재정렬
- 브레드크럼 내비게이션 반전
- 로그 형식 변환

**실행:**
```bash
./01-reverse-by-separator.sh
# 또는
cat 01-reverse-by-separator.sql | docker exec -i clickhouse-26-1 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- `reverseBySeparator(separator, string)`으로 부분 문자열 순서 반전
- 경로 정규화 및 형식 변환에 유용
- 모든 문자열 구분자 (/, ., -, 등)와 함께 작동
- 문자열의 빈 세그먼트 보존
- 다른 문자열 함수와 결합 가능
- URL 및 경로 조작에 효율적

**사용 사례:**
- URL 경로 조작 및 정규화
- 역방향 도메인 이름 조회 (PTR 레코드)
- 파일 경로 변환
- 로그 형식 변환
- 브레드크럼 내비게이션 구축
- CSV/TSV 컬럼 재정렬
- 네임스페이스 및 패키지 이름 처리
- 계층적 데이터 재구조화

---

#### 2. Text Index for Array Columns (02-text-index-arrays)

**새로운 기능:** 전체 텍스트 검색을 위해 Array 데이터 타입을 지원하도록 확장된 텍스트 인덱싱 기능

**테스트 내용:**
- Array(String) 컬럼에 텍스트 인덱스 생성
- 배열 내 다중 키워드 검색
- 태그 및 카테고리 검색 최적화
- 제품 기능 검색
- 댓글 및 리뷰 텍스트 검색
- 인덱스 유무에 따른 성능 비교

**실행:**
```bash
./02-text-index-arrays.sh
```

**주요 학습 포인트:**
- 텍스트 인덱스가 이제 `Array(String)` 컬럼에서 작동
- 배열 데이터 검색 성능을 크게 향상
- 일반 텍스트 인덱스와 동일한 구문 사용
- 다양한 토크나이저 지원 (ngrams, tokens 등)
- 태그, 카테고리 및 다중 값 필드 인덱싱 가능
- 배열 검색 쿼리 지연 시간 감소

**사용 사례:**
- 제품 태그 및 카테고리 검색
- 다중 키워드 기사 검색
- 전자상거래 필터 최적화
- 소셜 미디어 해시태그 검색
- 문서 키워드 인덱싱
- 사용자 관심사 및 선호도 검색
- 기술 및 역량 매칭
- 콘텐츠 추천 시스템

---

#### 3. HTTP API for ClickHouse Keeper (03-keeper-http-api)

**새로운 기능:** ClickHouse Keeper 모니터링 및 관리를 위한 내장 HTTP API 및 임베디드 웹 인터페이스

**테스트 내용:**
- HTTP API를 통한 Keeper 상태 접근
- 클러스터 구성 조회
- Keeper 메트릭 모니터링
- Znode 데이터 검사
- 헬스 체크 엔드포인트
- 웹 UI 탐색

**실행:**
```bash
./03-keeper-http-api.sh
```

**주요 학습 포인트:**
- Keeper에 이제 내장 HTTP API 포함
- Keeper의 HTTP 포트에서 웹 UI 사용 가능
- 상태, 구성 및 메트릭을 위한 REST 엔드포인트
- 모니터링을 위한 외부 도구 불필요
- 쉬운 통합을 위한 JSON 응답
- Keeper 운영 및 디버깅 단순화

**사용 사례:**
- Keeper 헬스 모니터링
- 클러스터 구성 검사
- 운영 대시보드
- 자동화된 헬스 체크
- 모니터링 도구와의 통합 (Prometheus, Grafana)
- Keeper 이슈 트러블슈팅
- Znode 데이터 검사
- 클러스터 상태 시각화

---

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
docker logs clickhouse-26-1

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
26.1/
├── README.md                        # 이 문서
├── 00-setup.sh                      # ClickHouse 26.1 설치 스크립트
├── 01-reverse-by-separator.sh       # reverseBySeparator 함수 테스트
├── 01-reverse-by-separator.sql      # reverseBySeparator SQL
├── 02-text-index-arrays.sh          # 배열 텍스트 인덱스 테스트
├── 02-text-index-arrays.sql         # 배열 텍스트 인덱스 SQL
├── 03-keeper-http-api.sh            # Keeper HTTP API 테스트
└── 03-keeper-http-api.sql           # Keeper HTTP API SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **01-reverse-by-separator** - 새로운 문자열 조작 함수 학습
3. **02-text-index-arrays** - 배열에 대한 전체 텍스트 검색 소개

#### 중급 사용자
1. **03-keeper-http-api** - Keeper 관리 및 모니터링 탐색
2. 배열의 텍스트 인덱스로 검색 기능 구축
3. 데이터 처리 파이프라인에 문자열 함수 통합

#### 고급 사용자
- 프로덕션 배열 컬럼에 텍스트 인덱스 적용
- Keeper 모니터링 대시보드 구축
- 새로운 기능으로 성능 최적화
- 외부 모니터링 시스템과 Keeper API 통합

### 🔍 추가 자료

- **Release Presentation**: [ClickHouse 26.1 Community Call](https://clickhouse.com/company/events/v26-01-community-release-call)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2026](https://clickhouse.com/docs/whats-new/changelog)
- **Newsletter**: [January 2026 Newsletter](https://clickhouse.com/blog/202601-newsletter)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 검사할 수 있습니다
- 모든 기능은 ClickHouse 26.1.1에서 검증되었습니다

### 🆕 26.1의 새로운 기능

- 유연한 텍스트 조작을 위한 reverseBySeparator를 포함한 **새로운 문자열 함수**
- Array 컬럼 지원으로 **텍스트 인덱스 강화**
- 내장 HTTP API 및 웹 UI로 **Keeper 개선**
- 데이터 읽기 시 skip 인덱스 기본 활성화를 포함한 **성능 최적화**
- 효율적인 행 수준 작업을 위한 deletion vector가 있는 **DeltaLake 지원**
- 기본 공통 타입으로 Variant 타입을 사용한 **향상된 타입 시스템**
- 개선된 JOIN 필터 푸시다운 및 윈도우 함수로 **쿼리 최적화**

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
