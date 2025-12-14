# ClickHouse 25.9 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.9 new features. This directory is designed for practical exercises and iterative learning of features newly added in ClickHouse 25.9.

### 📅 Release Information

- **Release Date**: September 2025
- **Version**: 25.9
- **Reference**: [ClickHouse Release 25.9](https://clickhouse.com/blog/clickhouse-release-25-09)
- **Release Statistics**: 25 new features, 22 performance optimizations, 83 bug fixes

### 📋 Overview

ClickHouse 25.9 includes automatic join optimization, full-text search indexes, streaming secondary indexes, and new array functions.

### 🎯 Key Features

1. **Automatic Global Join Reordering** - Statistics-based join optimization
2. **New Text Index** - Experimental full-text search capabilities
3. **Streaming Secondary Indices** - Faster query startup with incremental index reading
4. **arrayExcept Function** - Efficient array filtering

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) environment setup
- 8GB+ RAM recommended
- 10GB+ disk space

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.9
cd local/25.9
./00-setup.sh

# 2. Run tests for each feature
./01-join-reordering.sh      # Automatic join reordering
./02-text-index.sh           # Text index (full-text search)
./03-streaming-indices.sh    # Streaming secondary indexes
./05-array-except.sh         # arrayExcept function
```

#### What `./00-setup.sh` Does

The setup script performs the following:
- Configure ClickHouse 25.9 using oss-mac-setup
- Start ClickHouse on port 2509
- Verify installation
- Display connection information

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../oss-mac-setup
./client.sh 2509

# Execute SQL file
cd ../25.9
source 01-join-reordering.sql
```

### 📚 Feature Tests

#### 1. Automatic Global Join Reordering (01-join-reordering)

**What it does:** Automatically reorders multi-table joins based on table statistics and data volumes

**Test Content:**
- Creates tables of different sizes (countries: 100, products: 10K, orders: 1M, customers: 50K)
- Tests manual vs automatic join reordering
- Demonstrates 4-way join optimization
- Shows EXPLAIN output for join plans

**Execute:**
```bash
./01-join-reordering.sh
```

**Key Benefits:**
- Optimal join order automatically selected
- Reduced memory usage
- Faster query execution
- No manual query rewriting needed

**Example:**
```sql
-- Enable automatic join reordering
SET allow_experimental_join_reordering = 1;

SELECT
    c.continent,
    p.category,
    count() AS orders
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
GROUP BY c.continent, p.category;
```

---

#### 2. Text Index - Full-Text Search (02-text-index)

**What it does:** Provides experimental full-text search capabilities with streaming-friendly design

**Test Content:**
- Creates articles table with 10,000 records
- Tests full-text search queries
- Multi-term search patterns
- Category and time-based text search
- Author and tag analysis

**Execute:**
```bash
./02-text-index.sh
```

**Key Benefits:**
- Streaming-friendly architecture
- Efficient skip index granules
- Fast text matching
- Better than simple LIKE queries

**Example:**
```sql
CREATE TABLE articles
(
    article_id UInt64,
    title String,
    content String,
    INDEX content_idx content TYPE full_text GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY article_id;

-- Search for articles
SELECT title, content
FROM articles
WHERE content LIKE '%ClickHouse%';
```

---

#### 3. Streaming Secondary Indices (03-streaming-indices)

**What it does:** Reads indices incrementally alongside data scanning for faster query startup

**Test Content:**
- Creates events table with 5M records
- Compares streaming vs traditional index reading
- LIMIT query optimization
- Time-series analysis
- User behavior patterns

**Execute:**
```bash
./03-streaming-indices.sh
```

**Key Benefits:**
- Faster query startup
- Early query termination with LIMIT
- Incremental index reading
- Reduced memory overhead

**Example:**
```sql
-- Enable streaming indices
SET use_skip_indexes_on_data_read = 1;

CREATE TABLE events
(
    event_id UInt64,
    user_id UInt32,
    event_type String,
    INDEX user_idx user_id TYPE minmax GRANULARITY 4,
    INDEX type_idx event_type TYPE set(100) GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY event_id;

-- Query benefits from streaming indices
SELECT *
FROM events
WHERE user_id BETWEEN 1000 AND 2000
LIMIT 100;
```

---

#### 5. arrayExcept Function (05-array-except)

**What it does:** New function to filter arrays by removing elements from another array

**Test Content:**
- Basic array filtering
- User permission management
- Product feature filtering
- Tag management system
- Security rule filtering

**Execute:**
```bash
./05-array-except.sh
```

**Key Benefits:**
- Cleaner syntax than manual filtering
- Efficient array operations
- Works with any data type
- Maintains element order

**Example:**
```sql
-- Remove specific elements from array
SELECT arrayExcept([1, 2, 3, 4, 5], [2, 4]) AS result;
-- Result: [1, 3, 5]

-- Permission management
SELECT
    user_name,
    arrayExcept(all_permissions, revoked_permissions) AS active_permissions
FROM user_permissions;
```

### 🔧 Connection Information

After running `./00-setup.sh`:

- **Web UI**: http://localhost:2509/play
- **HTTP API**: http://localhost:2509
- **TCP Port**: localhost:25091
- **User**: default (no password)

### 🛠 Management Commands

#### ClickHouse Management

```bash
cd ../oss-mac-setup

# Check status
./status.sh

# Connect to CLI
./client.sh 2509

# Stop ClickHouse
./stop.sh
```

#### Data Verification

```bash
# Check tables
docker exec -it clickhouse-25-9 clickhouse-client -q "SHOW TABLES"

# Check version
curl http://localhost:2509/
```

### 📊 Test Data Summary

| Test | Table | Rows | Description |
|------|-------|------|-------------|
| Join Reordering | countries | 100 | Country dimension |
| Join Reordering | products | 10,000 | Product catalog |
| Join Reordering | orders | 1,000,000 | Order facts |
| Join Reordering | customers | 50,000 | Customer dimension |
| Text Index | articles | 10,000 | Article content |
| Streaming Indices | events | 5,000,000 | User events |
| arrayExcept | Various | Various | Permission/feature data |

### 🔍 Feature Status

| Feature | Status | Setting |
|---------|--------|---------|
| Join Reordering | Experimental | `allow_experimental_join_reordering = 1` |
| Text Index | Experimental | Built into table definition |
| Streaming Indices | Stable | `use_skip_indexes_on_data_read = 1` |
| arrayExcept | Stable | N/A (built-in function) |

### 📖 Additional Resources

- [ClickHouse 25.9 Release Blog](https://clickhouse.com/blog/clickhouse-release-25-09)
- [ClickHouse 25.9 Release Call](https://presentations.clickhouse.com/2025-release-25.9/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [ClickHouse GitHub Releases](https://github.com/ClickHouse/ClickHouse/releases)

### 🎓 Learning Path

#### For Beginners
1. Start with **arrayExcept** (easiest) - Array filtering basics
2. Try **Streaming Indices** (intermediate) - Index optimization
3. Explore **Text Index** (intermediate) - Full-text search implementation
4. Advanced: **Join Reordering** (advanced) - Complex join optimization

#### For Advanced Users
1. **Join Reordering** - Complex analytical query optimization
2. **Text Index** - Search functionality implementation
3. **Streaming Indices** - Performance tuning

### 🚨 Important Notes

- **Experimental Features**: Join Reordering and Text Index are experimental in 25.9
- **Settings Required**: Experimental features must be enabled with appropriate SET commands
- **Performance Testing**: Perform performance tests with actual data scale
- **Production Use**: Thorough testing required before production deployment

**Key Settings:**
- `SET allow_experimental_join_reordering = 1;` - Enable join reordering
- `SET use_skip_indexes_on_data_read = 1;` - Enable streaming indices

### 🧹 Cleanup

To stop and remove ClickHouse 25.9:

```bash
cd ../oss-mac-setup
./stop.sh

# Optional: Delete data
./cleanup.sh
```

### 📝 License

MIT License - See root directory for details

### 🤝 Contributing

Issues and pull requests welcome! Please refer to the main repository for contribution guidelines.

### 📬 Support

For questions or issues:
1. Check this README and test output
2. Review ClickHouse official documentation
3. Create an issue in the main repository

---

## 한국어

ClickHouse 25.9 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.9에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

### 📅 릴리스 정보

- **Release Date**: September 2025
- **Version**: 25.9
- **Reference**: [ClickHouse Release 25.9](https://clickhouse.com/blog/clickhouse-release-25-09)
- **Release Statistics**: 25 new features, 22 performance optimizations, 83 bug fixes

### 📋 개요

ClickHouse 25.9는 자동 조인 최적화, 전문 검색 인덱스, 스트리밍 보조 인덱스, 그리고 새로운 배열 함수를 포함합니다.

### 🎯 주요 기능

1. **Automatic Global Join Reordering** - 통계 기반 조인 최적화
2. **New Text Index** - 실험적 전문 검색 기능
3. **Streaming Secondary Indices** - 증분 인덱스 읽기로 더 빠른 쿼리 시작
4. **arrayExcept Function** - 효율적인 배열 필터링

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성
- 8GB+ RAM recommended
- 10GB+ disk space

#### 설정 및 실행

```bash
# 1. ClickHouse 25.9 설치 및 시작
cd local/25.9
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-join-reordering.sh      # 자동 조인 재정렬
./02-text-index.sh           # 텍스트 인덱스 (전문 검색)
./03-streaming-indices.sh    # 스트리밍 보조 인덱스
./05-array-except.sh         # arrayExcept 함수
```

#### `./00-setup.sh` 수행 내용

Setup 스크립트는 다음을 수행합니다:
- Configure ClickHouse 25.9 using oss-mac-setup
- Start ClickHouse on port 2509
- Verify installation
- Display connection information

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2509

# SQL 파일 실행
cd ../25.9
source 01-join-reordering.sql
```

### 📚 기능 테스트

#### 1. Automatic Global Join Reordering (01-join-reordering)

**기능:** 테이블 통계와 데이터 볼륨을 기반으로 다중 테이블 조인을 자동으로 재정렬

**테스트 내용:**
- Creates tables of different sizes (countries: 100, products: 10K, orders: 1M, customers: 50K)
- Tests manual vs automatic join reordering
- Demonstrates 4-way join optimization
- Shows EXPLAIN output for join plans

**실행:**
```bash
./01-join-reordering.sh
```

**주요 이점:**
- Optimal join order automatically selected
- Reduced memory usage
- Faster query execution
- No manual query rewriting needed

**예시:**
```sql
-- Enable automatic join reordering
SET allow_experimental_join_reordering = 1;

SELECT
    c.continent,
    p.category,
    count() AS orders
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN countries c ON o.country_id = c.country_id
GROUP BY c.continent, p.category;
```

---

#### 2. Text Index - Full-Text Search (02-text-index)

**기능:** 스트리밍 친화적 설계의 실험적 전문 검색 기능 제공

**테스트 내용:**
- Creates articles table with 10,000 records
- Tests full-text search queries
- Multi-term search patterns
- Category and time-based text search
- Author and tag analysis

**실행:**
```bash
./02-text-index.sh
```

**주요 이점:**
- Streaming-friendly architecture
- Efficient skip index granules
- Fast text matching
- Better than simple LIKE queries

**예시:**
```sql
CREATE TABLE articles
(
    article_id UInt64,
    title String,
    content String,
    INDEX content_idx content TYPE full_text GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY article_id;

-- Search for articles
SELECT title, content
FROM articles
WHERE content LIKE '%ClickHouse%';
```

---

#### 3. Streaming Secondary Indices (03-streaming-indices)

**기능:** 데이터 스캔과 함께 인덱스를 점진적으로 읽어 더 빠른 쿼리 시작

**테스트 내용:**
- Creates events table with 5M records
- Compares streaming vs traditional index reading
- LIMIT query optimization
- Time-series analysis
- User behavior patterns

**실행:**
```bash
./03-streaming-indices.sh
```

**주요 이점:**
- Faster query startup
- Early query termination with LIMIT
- Incremental index reading
- Reduced memory overhead

**예시:**
```sql
-- Enable streaming indices
SET use_skip_indexes_on_data_read = 1;

CREATE TABLE events
(
    event_id UInt64,
    user_id UInt32,
    event_type String,
    INDEX user_idx user_id TYPE minmax GRANULARITY 4,
    INDEX type_idx event_type TYPE set(100) GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY event_id;

-- Query benefits from streaming indices
SELECT *
FROM events
WHERE user_id BETWEEN 1000 AND 2000
LIMIT 100;
```

---

#### 5. arrayExcept Function (05-array-except)

**기능:** 다른 배열의 요소를 제거하여 배열을 필터링하는 새로운 함수

**테스트 내용:**
- Basic array filtering
- User permission management
- Product feature filtering
- Tag management system
- Security rule filtering

**실행:**
```bash
./05-array-except.sh
```

**주요 이점:**
- Cleaner syntax than manual filtering
- Efficient array operations
- Works with any data type
- Maintains element order

**예시:**
```sql
-- Remove specific elements from array
SELECT arrayExcept([1, 2, 3, 4, 5], [2, 4]) AS result;
-- Result: [1, 3, 5]

-- Permission management
SELECT
    user_name,
    arrayExcept(all_permissions, revoked_permissions) AS active_permissions
FROM user_permissions;
```

### 🔧 접속 정보

`./00-setup.sh` 실행 후:

- **Web UI**: http://localhost:2509/play
- **HTTP API**: http://localhost:2509
- **TCP Port**: localhost:25091
- **User**: default (no password)

### 🛠 관리 명령어

#### ClickHouse 관리

```bash
cd ../oss-mac-setup

# Check status
./status.sh

# Connect to CLI
./client.sh 2509

# Stop ClickHouse
./stop.sh
```

#### 데이터 확인

```bash
# Check tables
docker exec -it clickhouse-25-9 clickhouse-client -q "SHOW TABLES"

# Check version
curl http://localhost:2509/
```

### 📊 테스트 데이터 요약

| Test | Table | Rows | Description |
|------|-------|------|-------------|
| Join Reordering | countries | 100 | Country dimension |
| Join Reordering | products | 10,000 | Product catalog |
| Join Reordering | orders | 1,000,000 | Order facts |
| Join Reordering | customers | 50,000 | Customer dimension |
| Text Index | articles | 10,000 | Article content |
| Streaming Indices | events | 5,000,000 | User events |
| arrayExcept | Various | Various | Permission/feature data |

### 🔍 기능 상태

| Feature | Status | Setting |
|---------|--------|---------|
| Join Reordering | Experimental | `allow_experimental_join_reordering = 1` |
| Text Index | Experimental | Built into table definition |
| Streaming Indices | Stable | `use_skip_indexes_on_data_read = 1` |
| arrayExcept | Stable | N/A (built-in function) |

### 📖 추가 자료

- [ClickHouse 25.9 Release Blog](https://clickhouse.com/blog/clickhouse-release-25-09)
- [ClickHouse 25.9 Release Call](https://presentations.clickhouse.com/2025-release-25.9/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [ClickHouse GitHub Releases](https://github.com/ClickHouse/ClickHouse/releases)

### 🎓 학습 경로

#### 초급자용
1. Start with **arrayExcept** (가장 쉬움) - 배열 필터링 기초
2. Try **Streaming Indices** (중급) - 인덱스 최적화
3. Explore **Text Index** (중급) - 전문 검색 구현
4. Advanced: **Join Reordering** (고급) - 복잡한 조인 최적화

#### 고급 사용자용
1. **Join Reordering** - 복잡한 분석 쿼리 최적화
2. **Text Index** - 검색 기능 구축
3. **Streaming Indices** - 성능 튜닝

### 🚨 중요 참고사항

- **Experimental Features**: Join Reordering과 Text Index는 25.9에서 실험적 기능입니다
- **Settings Required**: 실험적 기능은 적절한 SET 명령으로 활성화해야 합니다
- **Performance Testing**: 실제 데이터 규모로 성능 테스트를 수행하세요
- **Production Use**: 프로덕션 환경에서 사용하기 전에 충분한 테스트를 거쳐야 합니다

**주요 설정:**
- `SET allow_experimental_join_reordering = 1;` - 조인 재정렬 활성화
- `SET use_skip_indexes_on_data_read = 1;` - 스트리밍 인덱스 활성화

### 🧹 정리

ClickHouse 25.9를 중지하고 제거하려면:

```bash
cd ../oss-mac-setup
./stop.sh

# Optional: 데이터 삭제
./cleanup.sh
```

### 📝 라이선스

MIT License - 자세한 내용은 루트 디렉토리를 참조하세요.

### 🤝 기여

Issues와 pull requests를 환영합니다! 기여 가이드라인은 메인 저장소를 참조해주세요.

### 📬 지원

질문이나 문제가 있으면:
1. 이 README와 테스트 출력을 확인하세요
2. ClickHouse 공식 문서를 검토하세요
3. 메인 저장소에 이슈를 생성하세요
