# ClickHouse 25.7 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

> **Related notes** (Korean): [ClickHouse Upsert 메커니즘의 발전 과정](https://clickhouse.litkhai.dev/articles/core-architecture/clickhouse-upsert/)

A hands-on laboratory for learning and testing ClickHouse 25.7 new features. This directory focuses on verified and working features newly added in ClickHouse 25.7 (released 2025-07-24).

### 📋 Overview

ClickHouse 25.7 adds `UPDATE ... SET ... WHERE` on patch parts (experimental), AI-powered SQL generation, count() aggregation optimization, and JOIN performance improvements.

### 🎯 Key Features

1. **SQL UPDATE and DELETE Operations** - `UPDATE ... SET ... WHERE` writes a small patch part instead of rewriting the data part; `DELETE FROM` for lightweight delete
2. **AI-Powered SQL Generation** - Natural language SQL generation using OpenAI/Anthropic API (?? prefix)
3. **count() Aggregation Optimization** - 20-30% faster aggregation performance and reduced memory usage
4. **JOIN Performance Improvements** - Up to 1.8x faster JOIN operations
5. **Bulk UPDATE Performance** - the same five bulk updates as `UPDATE` (patch parts) and as `ALTER TABLE ... UPDATE`, with the time and bytes written measured

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-docker](../../oss-docker/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.7
cd local/releases/25.7
./00-setup.sh

# 2. Run tests for each feature
./01-sql-update-delete.sh
./02-count-optimization.sh
./03-join-performance.sh
./04-bulk-update.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-docker
./client.sh 8123

# Execute SQL file
cd ../releases/25.7
source 01-sql-update-delete.sql
```

### 📚 Feature Details

#### 1. SQL UPDATE and DELETE Operations (01-sql-update-delete)

**New Feature:** `UPDATE t SET ... WHERE ...` using the patch-part mechanism (experimental in 25.7)

**Test Content:**
- The settings the server reports, and what it says when they are missing (`.sh`)
- `UPDATE` on a table with `enable_block_number_column = 1, enable_block_offset_column = 1`: the patch part in `system.parts`, no mutation
- `ALTER TABLE ... UPDATE` on an identical table: the mutation and the rewritten part
- What each wrote, from `system.part_log`
- `OPTIMIZE ... FINAL` folding the patch into the data part
- `DELETE FROM` (lightweight delete) shown as what it is
- 1,000,000 rows per table

**Execute:**
```bash
./01-sql-update-delete.sh
# Or
cat 01-sql-update-delete.sql | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- Needs, read from 25.7.8.71 (`system.settings`, `system.merge_tree_settings` and the error text): session setting `allow_experimental_lightweight_update = 1` (default 0; without it: Code 344), and on the table `enable_block_number_column = 1` and `enable_block_offset_column = 1` (default 0; without them: Code 48, one message per missing setting). Existing tables can get them with `ALTER TABLE ... MODIFY SETTING`
- Patch part: `UPDATE ... SET quantity = 0 WHERE category = 'Books'` (250,000 of 1,000,000 rows) created one patch part of 250,000 rows, 44,032 bytes on disk (8.3 MB uncompressed), next to the untouched data part. No entry in `system.mutations`. The new value is visible at once because patches are applied on `SELECT` (`apply_patch_parts`)
- `ALTER TABLE ... UPDATE` with the same predicate on an identical table: a mutation, and a new data part of 1,000,000 rows, 35,321,998 bytes on disk (44.0 MB uncompressed) replaced the old one
- The patch is merged into the data part by a merge (`OPTIMIZE ... FINAL`); read with `apply_patch_parts = 0` the merged part already holds the updated values
- `DELETE FROM t WHERE ...` is not a patch part: `system.mutations` shows `UPDATE _row_exists = 0 WHERE ...`, and the rows stay in the active parts until a merge
- You cannot `UPDATE` an ORDER BY key column (Code 420, `04-bulk-update.sh`)

**Real-World Use Cases:**
- Real-time inventory management and pricing adjustments
- E-commerce promotions and discount application
- Data quality improvement and correction tasks
- User profile and settings updates
- Batch data processing and ETL pipelines
- GDPR-compliant data deletion

**Size of what is written (this run, 1,000,000 rows, 250,000 updated):**
- `UPDATE` (patch part): 44,032 bytes on disk
- `ALTER TABLE ... UPDATE` (rewritten part): 35,321,998 bytes on disk
- Timings (tens to hundreds of milliseconds at this size) varied from run to run and are not quoted; no speed factor is claimed

---

#### 2. count() Aggregation Optimization (02-count-optimization)

**New Feature:** Optimized count() aggregation function (20-30% faster with reduced memory usage)

**Test Content:**
- Basic count() performance measurement
- count() optimization with GROUP BY
- count(DISTINCT) performance improvements
- Large dataset aggregation (10 million rows)
- Multi-dimensional aggregation scenarios
- Memory efficiency testing

**Execute:**
```bash
./02-count-optimization.sh
```

**Key Learning Points:**
- count() is the fastest aggregation function (utilizes metadata)
- count() is more efficient than count(column)
- 20-30% performance improvement with GROUP BY
- Memory optimization for count(DISTINCT)
- Conditional aggregation with countIf()
- count() used with window functions

**Real-World Use Cases:**
- Real-time analytics dashboards
- Large-scale event tracking and user behavior analysis
- Multi-dimensional business intelligence reporting
- Log aggregation and monitoring systems
- E-commerce conversion rate analysis
- IoT data processing and device telemetry

**Optimization Tips:**
- Use count() when possible (instead of count(column))
- Set appropriate indexes and ORDER BY keys
- Limit query scope using partitions
- Pre-aggregate with Materialized Views

---

#### 3. JOIN Performance Improvements (03-join-performance)

**New Feature:** Up to 1.8x faster JOIN operation performance

**Test Content:**
- INNER JOIN performance (up to 1.8x faster)
- LEFT JOIN optimization
- Multi-table JOIN (3 or more tables)
- JOIN and GROUP BY combination
- Complex analytical queries (subqueries, CTEs)
- Large dataset JOIN (millions to tens of millions of rows)

**Execute:**
```bash
./03-join-performance.sh
```

**Key Learning Points:**
- Hash table build and probing optimization
- Improved memory efficiency for large JOINs
- Enhanced multi-table JOIN query planning
- Optimal ordering of JOIN conditions
- RIGHT vs LEFT table selection strategy
- CTE (Common Table Expression) utilization

**Real-World Use Cases:**
- E-commerce customer and order analysis
- Multi-dimensional business intelligence dashboards
- Customer segmentation and cohort analysis
- Supply chain and inventory management reporting
- Financial reporting and transaction reconciliation
- Marketing attribution and campaign performance analysis

**Performance Optimization:**
- Place smaller table as RIGHT table
- Use appropriate data types for JOIN keys
- Don't SELECT unnecessary columns
- Filter data before JOIN with WHERE conditions

---

#### 4. Bulk UPDATE Performance (04-bulk-update)

**New Feature:** bulk `UPDATE` on patch parts, measured against `ALTER TABLE ... UPDATE`

**Test Content:**
- Two identical tables of 3,000,000 rows
- Five bulk updates (single category, several categories, compound WHERE, three columns at once, almost-every-row), run as `UPDATE` on one table and as `ALTER TABLE ... UPDATE` on the other
- Both tables end with the same data (row-hash sum compared)
- Time (`system.query_log`) and bytes written (`system.part_log`) for each way
- What `UPDATE` refuses (`.sh`): key column (Code 420), no WHERE (Code 62), table without the block settings (Code 48)

**Execute:**
```bash
./04-bulk-update.sh
```

**Key Learning Points:**
- Patch parts write only the changed rows; `ALTER TABLE ... UPDATE` rewrites the parts it touches
- Measured here (3,000,000 rows per table, 25.7.8.71, single local container, five statements each): `UPDATE` wrote 8 patch parts, 4,534,893 rows, about 7.5 MB on disk (198 MB uncompressed); `ALTER TABLE ... UPDATE` wrote 15 mutated parts, 15,000,000 rows, about 170 MB on disk (685 MB uncompressed)
- Time is not in favour of the patch here: over four runs the five `UPDATE` statements took 0.7 to 2.3 s in total and the five `ALTER TABLE ... UPDATE` (with `mutations_sync = 2`) 0.2 to 0.9 s. Fewer bytes written, not shorter wall time, is what this run shows
- Do not extrapolate: one small table, one node, cache state not controlled

**Real-World Use Cases:**
- Real-time inventory synchronization and pricing adjustments
- Retail: Daily closing price updates and promotions
- Finance: Bulk account balance adjustments
- Gaming: Player statistics and leaderboard updates
- IoT: Device configuration and status bulk updates
- Data migration: Legacy system modernization
- Data quality: Bulk correction and normalization

**Measured (3,000,000 rows, five bulk updates, one run):**

| Statement | New parts | Rows written | Bytes on disk | Statement time, total of five |
|-----------|-----------|--------------|---------------|-------------------------------|
| `UPDATE` (patch parts) | 8 | 4,534,893 | 7,476,049 | 1,432 ms |
| `ALTER TABLE ... UPDATE` | 15 | 15,000,000 | 169,986,047 | 157 ms |

The time column varied between runs (`UPDATE` 0.7-2.3 s, `ALTER` 0.2-0.9 s over four runs); the bytes moved by less than 0.2%. No comparison with another database was run.

---

#### 5. AI-Powered SQL Generation (Feature Description)

**New Feature:** Natural language to SQL conversion using OpenAI or Anthropic API

**Description:**
ClickHouse 25.7 provides AI-powered SQL generation that converts natural language to SQL using the `??` prefix.

**Usage:**
```sql
-- Using OpenAI API
SET openai_api_key = 'your-api-key';
?? show me top 10 customers by revenue

-- Using Anthropic API
SET anthropic_api_key = 'your-api-key';
?? calculate monthly growth rate for each product category
```

**Key Features:**
- Automatic conversion of natural language to SQL queries
- Automatic table schema analysis
- Generation of complex aggregation and JOIN queries
- Shortened learning curve and improved productivity
- Non-developers can perform data analysis

**Limitations:**
- Requires OpenAI or Anthropic API key
- API call costs incur
- Network connection required
- Generated query validation recommended

**Real-World Use Cases:**
- Self-service analytics for business analysts
- Rapid prototyping and exploratory analysis
- Education and SQL learning assistance
- Draft generation for complex queries

**Note:** This feature requires an API key, so this lab does not provide executable tests. Please refer to the examples above to test on your own.

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### Useful Commands

```bash
# Check ClickHouse status
cd ../../oss-docker
./status.sh

# Connect to CLI
./client.sh 8123

# View logs
docker logs clickhouse-25-7

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.7/
├── README.md                      # This document
├── 00-setup.sh                    # ClickHouse 25.7 installation script
├── 01-sql-update-delete.sh        # SQL UPDATE/DELETE test execution
├── 01-sql-update-delete.sql       # SQL UPDATE/DELETE SQL
├── 02-count-optimization.sh       # count() optimization test execution
├── 02-count-optimization.sql      # count() optimization SQL
├── 03-join-performance.sh         # JOIN performance test execution
├── 03-join-performance.sql        # JOIN performance SQL
├── 04-bulk-update.sh              # Bulk UPDATE test execution
└── 04-bulk-update.sql             # Bulk UPDATE SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **02-count-optimization** - Start with basic aggregation functions
3. **01-sql-update-delete** - Learn UPDATE/DELETE basics

#### For Intermediate Users
1. **03-join-performance** - Understand JOIN optimization
2. **04-bulk-update** - Learn bulk data processing
3. Explore AI-Powered SQL features (API key required)

#### For Advanced Users
- Combine all features for real production scenarios
- Analyze query execution plans with EXPLAIN
- Performance benchmarking and optimization
- Design real-time data pipelines

### 💡 Feature Comparison

#### ClickHouse 25.7 vs Previous Versions

| Feature | Before 25.7 | ClickHouse 25.7 | Improvement |
|---------|-------------|-----------------|-------------|
| UPDATE | `ALTER TABLE ... UPDATE` rewrites parts | `UPDATE` writes a patch part (experimental) | 44 KB vs 35 MB written in lab 01; time: see lab 04 |
| count() aggregation | Standard performance | Optimized | 20-30% faster |
| JOIN operations | Good performance | Enhanced | Up to 1.8x faster |
| Bulk UPDATE | Mutation rewrites parts | Patch parts | 7.5 MB vs 170 MB on disk in lab 04; slower wall time in that run |
| SQL Generation | Manual only | AI-powered (optional) | Natural language to SQL |

### 🆕 What's New in 25.7

- **Lightweight `UPDATE`** — patch-part based updates for MergeTree ([#82004](https://github.com/ClickHouse/ClickHouse/pull/82004))
- **AI-powered SQL generation** — natural language to SQL in the client ([#83314](https://github.com/ClickHouse/ClickHouse/pull/83314))
- **Financial functions** — `XIRR`, `IRR`, `XNPV`, `NPV` ([#81599](https://github.com/ClickHouse/ClickHouse/pull/81599))
- **`NumericIndexedVector`** — Roaring-bitmap compressed vector structure ([#74193](https://github.com/ClickHouse/ClickHouse/pull/74193))
- **Iceberg writes** — INSERT support for Iceberg tables ([#82692](https://github.com/ClickHouse/ClickHouse/pull/82692))
- **SZ3 lossy compression codec** — for `Float32` / `Float64` columns ([#67161](https://github.com/ClickHouse/ClickHouse/pull/67161))
- **Complex types in Iceberg schema evolution** — nested type evolution ([#73714](https://github.com/ClickHouse/ClickHouse/pull/73714))
- **`polygonIntersectsCartesian` / `Spherical`** — polygon intersection predicates ([#81882](https://github.com/ClickHouse/ClickHouse/pull/81882))
- **`colorSRGBToOkLCH` / `colorOkLCHToSRGB`** — colour space conversion ([#83679](https://github.com/ClickHouse/ClickHouse/pull/83679))
- **`_part_granule_offset`** — new MergeTree virtual column ([#82341](https://github.com/ClickHouse/ClickHouse/pull/82341))
- **`max_waiting_queries`** — workload setting bounding the query queue ([#81250](https://github.com/ClickHouse/ClickHouse/pull/81250))
- **Reading Iceberg data files by field id** — field-id based resolution ([#83653](https://github.com/ClickHouse/ClickHouse/pull/83653))

### 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.7 Release](https://clickhouse.com/blog/clickhouse-release-25-07)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 Notes

- All features verified on ClickHouse 25.7.8.71
- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default
- Thorough testing recommended before production use
- AI-Powered SQL feature requires an API key

### 🔒 Security Considerations

**When using UPDATE/DELETE operations:**
- Test carefully in production environment
- UPDATE without WHERE clause affects entire table
- Perform bulk updates after backup
- Monitor mutation queue

**When using AI-Powered SQL:**
- Manage API keys securely as environment variables
- Validate generated SQL before execution
- Access control for sensitive data
- Monitor API usage and costs

### ⚡ Performance Tips

**UPDATE/DELETE optimization:**
- Limit scope with appropriate WHERE conditions
- Efficient filtering using partition keys
- Utilize index keys in WHERE conditions
- Monitor mutation status (system.mutations table)

**count() optimization:**
- Use count() when possible (instead of count(column))
- Leverage indexes with appropriate ORDER BY keys
- Limit query scope using partitions
- Pre-aggregate with Materialized Views

**JOIN optimization:**
- Place smaller table as RIGHT table
- Use appropriate data types for JOIN keys
- Filter data before JOIN with WHERE
- Remove unnecessary columns

**Bulk UPDATE optimization:**
- Adjust batch size for memory efficiency
- Perform bulk updates during off-peak hours
- Distribute updates by partition
- Monitor progress

### 🚀 Production Deployment

#### Migration Strategy

1. **Validate in test environment**
   - Test all UPDATE/DELETE queries
   - Performance benchmarking
   - Establish rollback plan

2. **Gradual rollout**
   - Start with small tables
   - Monitor and measure performance
   - Immediate rollback on issues

3. **Monitoring**
   - Check mutation queue status
   - Monitor resource usage
   - Track query performance

#### Best Practices

```sql
-- Check mutation status
SELECT *
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time DESC;

-- Monitor running queries
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- Table part status
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;
```

### 🤝 Contributing

If you have improvements or additional examples for this lab:
1. Register an issue
2. Submit a Pull Request
3. Share feedback

### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../../README.md).

---

## 한국어

> **관련 글**: [ClickHouse Upsert 메커니즘의 발전 과정](https://clickhouse.litkhai.dev/articles/core-architecture/clickhouse-upsert/)

ClickHouse 25.7 신기능을 학습하고 테스트하는 실습 환경입니다. 이 디렉토리는 2025년 7월 24일 출시된 ClickHouse 25.7에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

### 📋 개요

ClickHouse 25.7은 patch part 기반 `UPDATE ... SET ... WHERE`(실험적), AI 기반 SQL 생성, count() 집계 최적화, JOIN 성능 개선을 포함합니다.

### 🎯 주요 기능

1. **SQL UPDATE and DELETE Operations** - `UPDATE ... SET ... WHERE`는 데이터 파트를 다시 쓰지 않고 작은 patch part를 씁니다. 경량 삭제는 `DELETE FROM`
2. **AI-Powered SQL Generation** - OpenAI/Anthropic API를 이용한 자연어 SQL 생성 (?? prefix)
3. **count() Aggregation Optimization** - 20-30% 빠른 집계 성능과 메모리 사용량 감소
4. **JOIN Performance Improvements** - 최대 1.8배 빠른 JOIN 연산
5. **Bulk UPDATE Performance** - 같은 대량 업데이트 5건을 `UPDATE`(patch part)와 `ALTER TABLE ... UPDATE`로 실행하고 시간과 기록한 바이트를 측정

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-docker](../../oss-docker/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 25.7 설치 및 시작
cd local/releases/25.7
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-sql-update-delete.sh
./02-count-optimization.sh
./03-join-performance.sh
./04-bulk-update.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-docker
./client.sh 8123

# SQL 파일 실행
cd ../releases/25.7
source 01-sql-update-delete.sql
```

### 📚 기능 상세

#### 1. SQL UPDATE and DELETE Operations (01-sql-update-delete)

**새로운 기능:** patch-part 메커니즘을 사용한 `UPDATE t SET ... WHERE ...` (25.7에서는 실험적)

**테스트 내용:**
- 서버가 보고하는 설정과, 설정이 없을 때의 오류(`.sh`)
- `enable_block_number_column = 1, enable_block_offset_column = 1` 테이블에서 `UPDATE`: `system.parts`의 patch part, mutation 없음
- 같은 테이블에서 `ALTER TABLE ... UPDATE`: mutation과 다시 쓴 파트
- `system.part_log`로 본 각각의 기록량
- `OPTIMIZE ... FINAL`이 patch를 데이터 파트에 합치는 과정
- `DELETE FROM`(경량 삭제)이 실제로 무엇인지
- 테이블당 1,000,000행

**실행:**
```bash
./01-sql-update-delete.sh
# 또는
cat 01-sql-update-delete.sql | docker exec -i clickhouse-25-7 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- 필요한 것(25.7.8.71의 `system.settings`, `system.merge_tree_settings`, 오류 메시지에서 확인): 세션 설정 `allow_experimental_lightweight_update = 1`(기본 0, 없으면 Code 344), 테이블 설정 `enable_block_number_column = 1`과 `enable_block_offset_column = 1`(기본 0, 없으면 Code 48, 빠진 설정마다 메시지 하나). 기존 테이블은 `ALTER TABLE ... MODIFY SETTING`으로 켤 수 있습니다
- Patch part: `UPDATE ... SET quantity = 0 WHERE category = 'Books'`(1,000,000행 중 250,000행)는 250,000행, 디스크 44,032바이트(비압축 8.3 MB)의 patch part 하나를 데이터 파트 옆에 만들었습니다. `system.mutations`에는 항목이 없습니다. `SELECT`가 patch를 적용(`apply_patch_parts`)하므로 새 값이 바로 보입니다
- 같은 조건의 `ALTER TABLE ... UPDATE`(동일한 테이블): mutation이 만들어지고 1,000,000행, 디스크 35,321,998바이트(비압축 44.0 MB)의 새 데이터 파트가 기존 파트를 대체했습니다
- patch는 머지(`OPTIMIZE ... FINAL`)로 데이터 파트에 합쳐집니다. `apply_patch_parts = 0`으로 읽어도 머지된 파트에는 이미 갱신된 값이 들어 있습니다
- `DELETE FROM t WHERE ...`는 patch part가 아닙니다. `system.mutations`에 `UPDATE _row_exists = 0 WHERE ...`가 보이고, 머지 전까지 행은 활성 파트에 남아 있습니다
- ORDER BY 키 컬럼은 `UPDATE`할 수 없습니다(Code 420, `04-bulk-update.sh`)

**실무 활용:**
- 실시간 재고 관리 및 가격 조정
- E-커머스 프로모션 및 할인 적용
- 데이터 품질 개선 및 정정 작업
- 사용자 프로필 및 설정 업데이트
- 배치 데이터 처리 및 ETL 파이프라인
- GDPR 준수를 위한 데이터 삭제

**기록량 (이번 실행, 1,000,000행 중 250,000행 갱신):**
- `UPDATE`(patch part): 디스크 44,032바이트
- `ALTER TABLE ... UPDATE`(다시 쓴 파트): 디스크 35,321,998바이트
- 이 크기에서 시간은 수십~수백 ms이고 실행마다 달라 싣지 않았습니다. 속도 배수는 주장하지 않습니다

---

#### 2. count() Aggregation Optimization (02-count-optimization)

**새로운 기능:** 최적화된 count() 집계 함수 (20-30% 빠르고 메모리 사용량 감소)

**테스트 내용:**
- 기본 count() 성능 측정
- GROUP BY와 함께 사용되는 count() 최적화
- count(DISTINCT) 성능 개선
- 대규모 데이터셋 (1000만 행) 집계
- 다차원 집계 시나리오
- 메모리 효율성 테스트

**실행:**
```bash
./02-count-optimization.sh
```

**주요 학습 포인트:**
- count()가 가장 빠른 집계 함수 (메타데이터 활용)
- count(column)보다 count()가 더 효율적
- GROUP BY와 함께 사용 시 20-30% 성능 향상
- count(DISTINCT)의 메모리 최적화
- countIf()를 이용한 조건부 집계
- 윈도우 함수와 함께 사용하는 count()

**실무 활용:**
- 실시간 분석 대시보드
- 대규모 이벤트 추적 및 사용자 행동 분석
- 다차원 비즈니스 인텔리전스 리포팅
- 로그 집계 및 모니터링 시스템
- E-커머스 전환율 분석
- IoT 데이터 처리 및 디바이스 텔레메트리

**최적화 팁:**
- 가능하면 count() 사용 (count(column) 대신)
- 적절한 인덱스와 ORDER BY 키 설정
- 파티션을 이용한 쿼리 범위 제한
- Materialized View로 사전 집계

---

#### 3. JOIN Performance Improvements (03-join-performance)

**새로운 기능:** 최대 1.8배 빠른 JOIN 연산 성능

**테스트 내용:**
- INNER JOIN 성능 (최대 1.8배 빠름)
- LEFT JOIN 최적화
- 다중 테이블 JOIN (3개 이상)
- JOIN과 GROUP BY 조합
- 복잡한 분석 쿼리 (서브쿼리, CTE)
- 대규모 데이터셋 JOIN (수백만-천만 행)

**실행:**
```bash
./03-join-performance.sh
```

**주요 학습 포인트:**
- 해시 테이블 구축 및 프로빙 최적화
- 대형 JOIN의 메모리 효율성 향상
- 다중 테이블 JOIN 쿼리 플래닝 개선
- JOIN 조건의 최적 순서
- RIGHT vs LEFT 테이블 선택 전략
- CTE(Common Table Expression) 활용

**실무 활용:**
- E-커머스 고객 및 주문 분석
- 다차원 비즈니스 인텔리전스 대시보드
- 고객 세그멘테이션 및 코호트 분석
- 공급망 및 재고 관리 리포팅
- 재무 리포팅 및 거래 조정
- 마케팅 어트리뷰션 및 캠페인 성능 분석

**성능 최적화:**
- 작은 테이블을 RIGHT 테이블로 배치
- JOIN 키에 적절한 데이터 타입 사용
- 불필요한 컬럼 SELECT 하지 않기
- WHERE 조건으로 JOIN 전 데이터 필터링

---

#### 4. Bulk UPDATE Performance (04-bulk-update)

**새로운 기능:** patch part 기반 대량 `UPDATE`를 `ALTER TABLE ... UPDATE`와 비교 측정

**테스트 내용:**
- 3,000,000행의 동일한 테이블 두 개
- 대량 업데이트 5건(한 카테고리, 여러 카테고리, 복합 WHERE, 세 컬럼 동시, 거의 모든 행)을 한 테이블에는 `UPDATE`로, 다른 테이블에는 `ALTER TABLE ... UPDATE`로 실행
- 두 테이블의 최종 데이터가 같은지 확인(행 해시 합 비교)
- 방식별 시간(`system.query_log`)과 기록한 바이트(`system.part_log`)
- `UPDATE`가 거부하는 경우(`.sh`): 키 컬럼(Code 420), WHERE 없음(Code 62), block 설정이 없는 테이블(Code 48)

**실행:**
```bash
./04-bulk-update.sh
```

**주요 학습 포인트:**
- patch part는 바뀐 행만 쓰고, `ALTER TABLE ... UPDATE`는 건드린 파트를 다시 씁니다
- 측정값(테이블당 3,000,000행, 25.7.8.71, 로컬 컨테이너 한 대, 각 5문장): `UPDATE`는 patch part 8개, 4,534,893행, 디스크 약 7.5 MB(비압축 198 MB)를 썼고, `ALTER TABLE ... UPDATE`는 변경된 파트 15개, 15,000,000행, 디스크 약 170 MB(비압축 685 MB)를 썼습니다
- 시간은 patch 쪽이 유리하지 않았습니다. 네 번 실행에서 `UPDATE` 5문장은 합계 0.7~2.3초, `ALTER TABLE ... UPDATE`(`mutations_sync = 2`) 5문장은 0.2~0.9초였습니다. 이번 실행이 보여주는 것은 짧은 시간이 아니라 적게 쓴 바이트입니다
- 일반화하지 마세요: 작은 테이블 하나, 노드 하나, 캐시 상태는 통제하지 않았습니다

**실무 활용:**
- 실시간 재고 동기화 및 가격 조정
- 소매업: 일일 마감 가격 업데이트 및 프로모션
- 금융: 대량 계좌 잔액 조정
- 게임: 플레이어 통계 및 리더보드 업데이트
- IoT: 디바이스 구성 및 상태 대량 업데이트
- 데이터 마이그레이션: 레거시 시스템 현대화
- 데이터 품질: 대량 정정 및 정규화

**측정값 (3,000,000행, 대량 업데이트 5건, 한 번 실행):**

| 문장 | 새 파트 | 기록한 행 | 디스크 바이트 | 문장 시간(5건 합계) |
|------|---------|-----------|---------------|---------------------|
| `UPDATE` (patch part) | 8 | 4,534,893 | 7,476,049 | 1,432 ms |
| `ALTER TABLE ... UPDATE` | 15 | 15,000,000 | 169,986,047 | 157 ms |

시간 열은 실행마다 달랐고(네 번 실행: `UPDATE` 0.7~2.3초, `ALTER` 0.2~0.9초), 바이트는 0.2% 미만으로 움직였습니다. 다른 데이터베이스와의 비교는 실행하지 않았습니다.

---

#### 5. AI-Powered SQL Generation (기능 설명)

**새로운 기능:** OpenAI 또는 Anthropic API를 이용한 자연어 SQL 생성

**설명:**
ClickHouse 25.7은 `??` prefix를 사용하여 자연어를 SQL로 변환하는 AI 기반 SQL 생성 기능을 제공합니다.

**사용 방법:**
```sql
-- OpenAI API 사용
SET openai_api_key = 'your-api-key';
?? show me top 10 customers by revenue

-- Anthropic API 사용
SET anthropic_api_key = 'your-api-key';
?? calculate monthly growth rate for each product category
```

**주요 특징:**
- 자연어를 SQL 쿼리로 자동 변환
- 테이블 스키마 자동 분석
- 복잡한 집계 및 JOIN 쿼리 생성
- 학습 곡선 단축 및 생산성 향상
- 비개발자도 데이터 분석 가능

**제약 사항:**
- OpenAI 또는 Anthropic API 키 필요
- API 호출 비용 발생
- 네트워크 연결 필요
- 생성된 쿼리 검증 권장

**실무 활용:**
- 비즈니스 분석가의 셀프 서비스 분석
- 빠른 프로토타이핑 및 탐색적 분석
- 교육 및 SQL 학습 보조
- 복잡한 쿼리의 초안 생성

**참고:** 이 기능은 API 키가 필요하므로 이 lab에서는 실행 가능한 테스트를 제공하지 않습니다. 위의 예제를 참고하여 직접 테스트해보세요.

### 🔧 관리

#### ClickHouse 접속 정보

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### 유용한 명령어

```bash
# ClickHouse 상태 확인
cd ../../oss-docker
./status.sh

# CLI 접속
./client.sh 8123

# 로그 확인
docker logs clickhouse-25-7

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.7/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.7 설치 스크립트
├── 01-sql-update-delete.sh        # SQL UPDATE/DELETE 테스트 실행
├── 01-sql-update-delete.sql       # SQL UPDATE/DELETE SQL
├── 02-count-optimization.sh       # count() 최적화 테스트 실행
├── 02-count-optimization.sql      # count() 최적화 SQL
├── 03-join-performance.sh         # JOIN 성능 테스트 실행
├── 03-join-performance.sql        # JOIN 성능 SQL
├── 04-bulk-update.sh              # Bulk UPDATE 테스트 실행
└── 04-bulk-update.sql             # Bulk UPDATE SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-count-optimization** - 기본 집계 함수부터 시작
3. **01-sql-update-delete** - UPDATE/DELETE 기초 학습

#### 중급 사용자
1. **03-join-performance** - JOIN 최적화 이해
2. **04-bulk-update** - 대량 데이터 처리 학습
3. AI-Powered SQL 기능 탐색 (API 키 필요)

#### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 최적화
- 실시간 데이터 파이프라인 설계

### 💡 기능 비교

#### ClickHouse 25.7 vs Previous Versions

| Feature | Before 25.7 | ClickHouse 25.7 | Improvement |
|---------|-------------|-----------------|-------------|
| UPDATE | `ALTER TABLE ... UPDATE` rewrites parts | `UPDATE` writes a patch part (experimental) | 44 KB vs 35 MB written in lab 01; time: see lab 04 |
| count() aggregation | Standard performance | Optimized | 20-30% faster |
| JOIN operations | Good performance | Enhanced | Up to 1.8x faster |
| Bulk UPDATE | Mutation rewrites parts | Patch parts | 7.5 MB vs 170 MB on disk in lab 04; slower wall time in that run |
| SQL Generation | Manual only | AI-powered (optional) | Natural language to SQL |

### 🆕 25.7의 새로운 기능

- **Lightweight `UPDATE`** — patch-part based updates for MergeTree ([#82004](https://github.com/ClickHouse/ClickHouse/pull/82004))
- **AI-powered SQL generation** — natural language to SQL in the client ([#83314](https://github.com/ClickHouse/ClickHouse/pull/83314))
- **Financial functions** — `XIRR`, `IRR`, `XNPV`, `NPV` ([#81599](https://github.com/ClickHouse/ClickHouse/pull/81599))
- **`NumericIndexedVector`** — Roaring-bitmap compressed vector structure ([#74193](https://github.com/ClickHouse/ClickHouse/pull/74193))
- **Iceberg writes** — INSERT support for Iceberg tables ([#82692](https://github.com/ClickHouse/ClickHouse/pull/82692))
- **SZ3 lossy compression codec** — for `Float32` / `Float64` columns ([#67161](https://github.com/ClickHouse/ClickHouse/pull/67161))
- **Complex types in Iceberg schema evolution** — nested type evolution ([#73714](https://github.com/ClickHouse/ClickHouse/pull/73714))
- **`polygonIntersectsCartesian` / `Spherical`** — polygon intersection predicates ([#81882](https://github.com/ClickHouse/ClickHouse/pull/81882))
- **`colorSRGBToOkLCH` / `colorOkLCHToSRGB`** — colour space conversion ([#83679](https://github.com/ClickHouse/ClickHouse/pull/83679))
- **`_part_granule_offset`** — new MergeTree virtual column ([#82341](https://github.com/ClickHouse/ClickHouse/pull/82341))
- **`max_waiting_queries`** — workload setting bounding the query queue ([#81250](https://github.com/ClickHouse/ClickHouse/pull/81250))
- **Reading Iceberg data files by field id** — field-id based resolution ([#83653](https://github.com/ClickHouse/ClickHouse/pull/83653))

### 🔍 추가 자료

- **Official Release Blog**: [ClickHouse 25.7 Release](https://clickhouse.com/blog/clickhouse-release-25-07)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다
- AI-Powered SQL 기능은 API 키가 필요합니다

### 🔒 보안 고려사항

**UPDATE/DELETE 연산 사용 시:**
- 프로덕션 환경에서는 신중하게 테스트
- WHERE 조건 없는 UPDATE는 전체 테이블 영향
- 백업 후 대량 업데이트 수행 권장
- Mutation 큐 모니터링

**AI-Powered SQL 사용 시:**
- API 키는 환경 변수로 안전하게 관리
- 생성된 SQL은 실행 전 검증
- 민감한 데이터에 대한 접근 제어
- API 사용량 및 비용 모니터링

### ⚡ 성능 팁

**UPDATE/DELETE 최적화:**
- 적절한 WHERE 조건으로 범위 제한
- 파티션 키를 이용한 효율적인 필터링
- 인덱스 키를 WHERE 조건에 활용
- Mutation 상태 모니터링 (system.mutations 테이블)

**count() 최적화:**
- 가능하면 count() 사용 (count(column) 대신)
- 적절한 ORDER BY 키로 인덱스 활용
- 파티션을 이용한 쿼리 범위 제한
- Materialized View로 사전 집계

**JOIN 최적화:**
- 작은 테이블을 RIGHT 테이블로
- JOIN 키에 적절한 데이터 타입
- WHERE로 JOIN 전 데이터 필터링
- 불필요한 컬럼 제거

**Bulk UPDATE 최적화:**
- 배치 크기 조정으로 메모리 효율성
- 오프피크 시간에 대량 업데이트 수행
- 파티션별로 업데이트 분산
- 진행 상황 모니터링

### 🚀 프로덕션 배포

#### 마이그레이션 전략

1. **테스트 환경에서 검증**
   - 모든 UPDATE/DELETE 쿼리 테스트
   - 성능 벤치마킹
   - 롤백 계획 수립

2. **점진적 롤아웃**
   - 작은 테이블부터 시작
   - 모니터링 및 성능 측정
   - 문제 발생 시 즉시 롤백

3. **모니터링**
   - Mutation 큐 상태 확인
   - 리소스 사용량 모니터링
   - 쿼리 성능 추적

#### Best Practices

```sql
-- Mutation 상태 확인
SELECT *
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time DESC;

-- 실행 중인 쿼리 모니터링
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- 테이블 파트 상태
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;
```

### 🤝 기여

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**

질문이나 이슈가 있으면 메인 [clickhouse-hols README](../../../README.md)를 참조하세요.
