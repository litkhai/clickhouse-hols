# ClickHouse 25.6 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.6 new features. This directory focuses on verified and working features newly added in ClickHouse 25.6 (released 2025-06-26).

### 📋 Overview

ClickHouse 25.6 includes CoalescingMergeTree table engine, new Time data types, Bech32 encoding functions, lag/lead window functions, and consistent snapshot capabilities.

### 🎯 Key Features

1. **CoalescingMergeTree** - New table engine optimized for sparse updates
2. **Time and Time64 Data Types** - New data types for time-of-day representation
3. **Bech32 Encoding Functions** - Bech32 encoding/decoding for cryptocurrency addresses
4. **lag/lead Window Functions** - Window functions for SQL compatibility
5. **Consistent Snapshot** - Consistent data snapshots across multiple queries

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment setup

#### Setup and Run

```bash
# 1. Install and start ClickHouse 25.6
cd local/releases/25.6
./00-setup.sh

# 2. Run tests for each feature
./01-coalescingmergetree.sh
./02-time-datatypes.sh
./03-bech32-encoding.sh
./04-lag-lead-functions.sh
./05-consistent-snapshot.sh
```

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../../oss-mac-setup
./client.sh 8123

# Execute SQL file
cd ../releases/25.6
source 01-coalescingmergetree.sql
```

### 📚 Feature Details

#### 1. CoalescingMergeTree (01-coalescingmergetree)

**New Feature:** CoalescingMergeTree table engine optimized for sparse updates

**Test Content:**
- Create tables using CoalescingMergeTree engine
- Handle updates/deletes using Sign column
- Verify automatic merge behavior
- Sensor data and metrics tracking use cases
- Real-time data modification scenarios

**Execute:**
```bash
./01-coalescingmergetree.sh
# Or
cat 01-coalescingmergetree.sql | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- Sign column: 1 for insert, -1 for delete/update (previous value)
- Automatic merge based on Sign value during merge
- More efficient than ReplacingMergeTree for frequent updates
- Suitable for CDC (Change Data Capture) scenarios

**Real-World Use Cases:**
- Metrics and monitoring systems
- Sensor data correction and calibration
- User state tracking
- Real-time dashboard updates

---

#### 2. Time and Time64 Data Types (02-time-datatypes)

**New Feature:** Time and Time64 data types for time-of-day representation

**Test Content:**
- Time data type (second precision)
- Time64 data type (microsecond precision)
- Time arithmetic and calculations
- Business hours scheduling
- API performance monitoring

**Execute:**
```bash
./02-time-datatypes.sh
```

**Key Learning Points:**
- `Time`: Stored as seconds since midnight
- `Time64(precision)`: Supports microsecond precision
- Time arithmetic: add, subtract, difference calculations
- Efficient storage by storing time only, without date
- Business operating hours and work time management

**Real-World Use Cases:**
- Business hours and operating schedules
- Employee shift management
- API response time monitoring (microsecond precision)
- Service availability and SLA tracking
- Time-based access control

---

#### 3. Bech32 Encoding Functions (03-bech32-encoding)

**New Feature:** Bech32 encoding/decoding functions (`bech32Encode`, `bech32Decode`)

**Test Content:**
- Encode data using bech32Encode() function
- Decode using bech32Decode() function
- HRP (Human Readable Prefix) handling
- Cryptocurrency address encoding
- Checksum validation and error detection

**Execute:**
```bash
./03-bech32-encoding.sh
```

**Key Learning Points:**
- Bech32 is a Base32 variant with checksum
- HRP identifies the purpose of encoded data
- Case insensitive (reduces input errors)
- Excludes confusable characters (0, O, I, l)
- Used in Bitcoin Segwit addresses

**Real-World Use Cases:**
- Cryptocurrency address encoding
- Public API key generation
- URL shortening and obfuscation
- Invoice and payment identifiers
- External ID mapping for security
- QR code data encoding

---

#### 4. lag/lead Window Functions (04-lag-lead-functions)

**New Feature:** `lag()` and `lead()` window functions for accessing previous/next rows

**Test Content:**
- Access previous row data with lag() function
- Access next row data with lead() function
- Window partitioning and ordering
- Time series analysis and trend detection
- Customer behavior and conversion tracking

**Execute:**
```bash
./04-lag-lead-functions.sh
```

**Key Learning Points:**
- `lag(column, offset, default)`: Previous offset-th row
- `lead(column, offset, default)`: Next offset-th row
- PARTITION BY for independent windows per group
- Compare adjacent rows without self-join
- Calculate change rates in time series data

**Real-World Use Cases:**
- Stock price analysis and daily return calculation
- User behavior analysis and conversion funnel
- Revenue trend detection and forecasting
- Moving averages and time series smoothing
- Session analysis and user journey mapping
- Anomaly detection compared to previous period

---

#### 5. Consistent Snapshot (05-consistent-snapshot)

**New Feature:** Consistent snapshot guarantee across multiple queries

**Test Content:**
- Snapshot isolation for read consistency
- Multi-query transactions using snapshot_id
- Prevent phantom reads during long-running operations
- Generate reports with consistent data
- Audit and compliance scenarios

**Execute:**
```bash
./05-consistent-snapshot.sh
```

**Key Learning Points:**
- Ensure multiple queries see the same data state
- Maintain data consistency during report generation
- Point-in-time analysis through snapshot tables
- Generate checksums for audit trails
- Historical snapshots for regulatory reporting

**Real-World Use Cases:**
- Financial end-of-day reports and reconciliation
- Regulatory compliance and audit trails
- Consistent multi-table dashboard generation
- Export data to external systems
- Historical point-in-time analysis
- Backup validation and data integrity checks

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
docker logs clickhouse-25-6

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.6/
├── README.md                      # This document
├── 00-setup.sh                    # ClickHouse 25.6 installation script
├── 01-coalescingmergetree.sh      # CoalescingMergeTree test execution
├── 01-coalescingmergetree.sql     # CoalescingMergeTree SQL
├── 02-time-datatypes.sh           # Time data type test execution
├── 02-time-datatypes.sql          # Time data type SQL
├── 03-bech32-encoding.sh          # Bech32 encoding test execution
├── 03-bech32-encoding.sql         # Bech32 encoding SQL
├── 04-lag-lead-functions.sh       # lag/lead function test execution
├── 04-lag-lead-functions.sql      # lag/lead function SQL
├── 05-consistent-snapshot.sh      # Consistent Snapshot test execution
└── 05-consistent-snapshot.sql     # Consistent Snapshot SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **02-time-datatypes** - Start with simple data types
3. **04-lag-lead-functions** - Learn window function basics

#### For Intermediate Users
1. **01-coalescingmergetree** - Understand table engine optimization
2. **03-bech32-encoding** - Encoding and security concepts
3. **05-consistent-snapshot** - Transaction and consistency

#### For Advanced Users
- Combine all features for real production scenarios
- Analyze query execution plans with EXPLAIN
- Performance benchmarking and comparison
- Design real-time data pipelines

### 💡 Feature Comparison

#### CoalescingMergeTree vs ReplacingMergeTree

| Feature | CoalescingMergeTree | ReplacingMergeTree |
|---------|---------------------|-------------------|
| Update method | Sign column (-1, +1) | Version column |
| Merge timing | Automatic merge | FINAL query required |
| Performance | Good for frequent updates | Good for rare updates |
| Use case | Metrics, CDC | Master data, dimension tables |

#### Time vs DateTime

| Feature | Time/Time64 | DateTime |
|---------|-------------|----------|
| Storage content | Time only (since midnight) | Date + Time |
| Precision | Seconds or microseconds | Seconds |
| Use case | Business hours, schedules | Timestamps, events |
| Storage size | Smaller | Larger |

### 🆕 What's New in 25.6

- **`CoalescingMergeTree`** — engine for sparse updates ([#79344](https://github.com/ClickHouse/ClickHouse/pull/79344))
- **`Time` / `Time64` data types** — time-of-day types with cast functions ([#81217](https://github.com/ClickHouse/ClickHouse/pull/81217))
- **Bech32 encoding functions** — `bech32Encode` / `bech32Decode` ([#80239](https://github.com/ClickHouse/ClickHouse/pull/80239))
- **`lag` / `lead` window functions** — SQL-standard offset windows ([#82108](https://github.com/ClickHouse/ClickHouse/pull/82108))
- **Consistent storage snapshots across subqueries** — shared snapshot setting ([#79471](https://github.com/ClickHouse/ClickHouse/pull/79471))
- **Writing to the `Merge` table engine** — `Merge` is no longer read-only ([#77484](https://github.com/ClickHouse/ClickHouse/pull/77484))
- **Map value functions** — `mapContainsValues`, `mapExtractValuesLike` and friends ([#78171](https://github.com/ClickHouse/ClickHouse/pull/78171))
- **Query slot scheduling for workloads** — workload-level concurrency control ([#78415](https://github.com/ClickHouse/ClickHouse/pull/78415))
- **JSON columns in Parquet** — read and write ClickHouse JSON as Parquet JSON ([#79649](https://github.com/ClickHouse/ClickHouse/pull/79649))
- **`deltaLakeLocal`** — query filesystem-mounted Delta tables ([#79781](https://github.com/ClickHouse/ClickHouse/pull/79781))
- **WKB reader functions** — read Well-Known Binary geometries ([#80139](https://github.com/ClickHouse/ClickHouse/pull/80139))
- **`MultiPolygon` in `pointInPolygon`** — multi-polygon containment ([#79773](https://github.com/ClickHouse/ClickHouse/pull/79773))
- **`timeSeries*` helper functions** — time series operations ([#80590](https://github.com/ClickHouse/ClickHouse/pull/80590))
- **`USE DATABASE`** — standard database switching syntax ([#81307](https://github.com/ClickHouse/ClickHouse/pull/81307))
- **`system.codecs`** — introspect available compression codecs ([#81600](https://github.com/ClickHouse/ClickHouse/pull/81600))
- **chdig TUI** — bundled terminal UI for ClickHouse ([#79666](https://github.com/ClickHouse/ClickHouse/pull/79666))

### 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.6 Release](https://clickhouse.com/blog/clickhouse-release-25-06)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 Notes

- All features verified on ClickHouse 25.6.13.41
- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default
- Thorough testing recommended before production use

### 🔒 Security Considerations

**When using Bech32 encoding:**
- Includes checksum but is not encryption
- Additional encryption needed for sensitive data
- Use only as public identifier

**When using CoalescingMergeTree:**
- Be careful with Sign column management
- Ensure consistency at application level
- Consider concurrency control mechanisms

### ⚡ Performance Tips

**CoalescingMergeTree:**
- Improve merge efficiency with appropriate ORDER BY keys
- Manage historical data with partition strategy
- Optimize read performance with Sign filtering

**Time64 data type:**
- Use Time64 only when high precision is needed
- Time is sufficient for most cases
- Can be used as index and partition key

**lag/lead functions:**
- Limit window size with appropriate PARTITION BY
- Reduce sort cost with ORDER BY optimization
- Large offset values affect performance

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

ClickHouse 25.6 신기능을 학습하고 테스트하는 실습 환경입니다. 이 디렉토리는 2025년 6월 26일 출시된 ClickHouse 25.6에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있습니다.

### 📋 개요

ClickHouse 25.6은 CoalescingMergeTree 테이블 엔진, 새로운 Time 데이터 타입, Bech32 인코딩 함수, lag/lead 윈도우 함수, 그리고 일관된 스냅샷 기능을 포함합니다.

### 🎯 주요 기능

1. **CoalescingMergeTree** - 희소 업데이트에 최적화된 새로운 테이블 엔진
2. **Time and Time64 Data Types** - 시간 표현을 위한 새로운 데이터 타입
3. **Bech32 Encoding Functions** - 암호화폐 주소 등에 사용되는 Bech32 인코딩/디코딩
4. **lag/lead Window Functions** - SQL 호환성을 위한 윈도우 함수
5. **Consistent Snapshot** - 여러 쿼리에 걸친 일관된 데이터 스냅샷

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) 환경 구성

#### 설정 및 실행

```bash
# 1. ClickHouse 25.6 설치 및 시작
cd local/releases/25.6
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-coalescingmergetree.sh
./02-time-datatypes.sh
./03-bech32-encoding.sh
./04-lag-lead-functions.sh
./05-consistent-snapshot.sh
```

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../../oss-mac-setup
./client.sh 8123

# SQL 파일 실행
cd ../releases/25.6
source 01-coalescingmergetree.sql
```

### 📚 기능 상세

#### 1. CoalescingMergeTree (01-coalescingmergetree)

**새로운 기능:** 희소 업데이트에 최적화된 CoalescingMergeTree 테이블 엔진

**테스트 내용:**
- CoalescingMergeTree 엔진을 사용한 테이블 생성
- Sign 컬럼을 이용한 업데이트/삭제 처리
- 머지 시 자동 병합 동작 확인
- 센서 데이터 및 메트릭 추적 사용 사례
- 실시간 데이터 수정 시나리오

**실행:**
```bash
./01-coalescingmergetree.sh
# 또는
cat 01-coalescingmergetree.sql | docker exec -i clickhouse-25-6 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- Sign 컬럼: 1은 삽입, -1은 삭제/업데이트(이전 값)
- 머지 시 Sign 값을 기반으로 자동 병합
- ReplacingMergeTree보다 빈번한 업데이트에 효율적
- CDC(Change Data Capture) 시나리오에 적합

**실무 활용:**
- 메트릭 및 모니터링 시스템
- 센서 데이터 수정 및 보정
- 사용자 상태 추적
- 실시간 대시보드 업데이트

---

#### 2. Time and Time64 Data Types (02-time-datatypes)

**새로운 기능:** 시간(time-of-day) 표현을 위한 Time 및 Time64 데이터 타입

**테스트 내용:**
- Time 데이터 타입 (초 정밀도)
- Time64 데이터 타입 (마이크로초 정밀도)
- 시간 연산 및 계산
- 비즈니스 시간 스케줄링
- API 성능 모니터링

**실행:**
```bash
./02-time-datatypes.sh
```

**주요 학습 포인트:**
- `Time`: 자정 이후 초 단위로 저장
- `Time64(precision)`: 마이크로초 정밀도 지원
- 시간 산술 연산: 더하기, 빼기, 차이 계산
- 날짜 없이 시간만 저장하여 효율적인 스토리지
- 비즈니스 운영 시간 및 근무 시간 관리

**실무 활용:**
- 영업 시간 및 운영 스케줄
- 직원 교대 근무 관리
- API 응답 시간 모니터링 (마이크로초 단위)
- 서비스 가용성 및 SLA 추적
- 시간 기반 접근 제어

---

#### 3. Bech32 Encoding Functions (03-bech32-encoding)

**새로운 기능:** Bech32 인코딩/디코딩 함수 (`bech32Encode`, `bech32Decode`)

**테스트 내용:**
- bech32Encode() 함수를 이용한 데이터 인코딩
- bech32Decode() 함수를 이용한 디코딩
- HRP(Human Readable Prefix) 처리
- 암호화폐 주소 인코딩
- 체크섬 검증 및 오류 감지

**실행:**
```bash
./03-bech32-encoding.sh
```

**주요 학습 포인트:**
- Bech32는 Base32 변형으로 체크섬 포함
- HRP로 인코딩된 데이터의 용도 식별
- 대소문자 구분 없음 (입력 오류 감소)
- 혼동 가능한 문자 제외 (0, O, I, l)
- 비트코인 Segwit 주소 등에 사용

**실무 활용:**
- 암호화폐 주소 인코딩
- 공개 API 키 생성
- URL 단축 및 난독화
- 인보이스 및 결제 식별자
- 보안을 위한 외부 ID 매핑
- QR 코드 데이터 인코딩

---

#### 4. lag/lead Window Functions (04-lag-lead-functions)

**새로운 기능:** 이전/다음 행 접근을 위한 `lag()` 및 `lead()` 윈도우 함수

**테스트 내용:**
- lag() 함수로 이전 행 데이터 접근
- lead() 함수로 다음 행 데이터 접근
- 윈도우 파티셔닝 및 정렬
- 시계열 분석 및 추세 감지
- 고객 행동 및 전환 추적

**실행:**
```bash
./04-lag-lead-functions.sh
```

**주요 학습 포인트:**
- `lag(column, offset, default)`: 이전 offset번째 행
- `lead(column, offset, default)`: 다음 offset번째 행
- PARTITION BY로 그룹별 독립적인 윈도우
- 셀프 조인 없이 인접 행 비교 가능
- 시계열 데이터의 변화율 계산

**실무 활용:**
- 주식 가격 분석 및 일일 수익률 계산
- 사용자 행동 분석 및 전환 퍼널
- 매출 추세 감지 및 예측
- 이동 평균 및 시계열 스무딩
- 세션 분석 및 사용자 여정 매핑
- 이전 기간 대비 이상 감지

---

#### 5. Consistent Snapshot (05-consistent-snapshot)

**새로운 기능:** 여러 쿼리에 걸친 일관된 스냅샷 보장

**테스트 내용:**
- 읽기 일관성을 위한 스냅샷 격리
- snapshot_id를 사용한 다중 쿼리 트랜잭션
- 장시간 작업 중 팬텀 읽기 방지
- 일관된 데이터로 리포트 생성
- 감사 및 규정 준수 시나리오

**실행:**
```bash
./05-consistent-snapshot.sh
```

**주요 학습 포인트:**
- 여러 쿼리가 동일한 데이터 상태를 보도록 보장
- 리포트 생성 중 데이터 일관성 유지
- 스냅샷 테이블을 통한 특정 시점 분석
- 감사 추적을 위한 체크섬 생성
- 규제 보고를 위한 히스토리컬 스냅샷

**실무 활용:**
- 재무 일일 마감 리포트 및 정산
- 규제 준수 및 감사 추적
- 일관성 있는 다중 테이블 대시보드 생성
- 외부 시스템으로 데이터 내보내기
- 히스토리컬 특정 시점 분석
- 백업 검증 및 데이터 무결성 검사

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
docker logs clickhouse-25-6

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.6/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.6 설치 스크립트
├── 01-coalescingmergetree.sh      # CoalescingMergeTree 테스트 실행
├── 01-coalescingmergetree.sql     # CoalescingMergeTree SQL
├── 02-time-datatypes.sh           # Time 데이터 타입 테스트 실행
├── 02-time-datatypes.sql          # Time 데이터 타입 SQL
├── 03-bech32-encoding.sh          # Bech32 인코딩 테스트 실행
├── 03-bech32-encoding.sql         # Bech32 인코딩 SQL
├── 04-lag-lead-functions.sh       # lag/lead 함수 테스트 실행
├── 04-lag-lead-functions.sql      # lag/lead 함수 SQL
├── 05-consistent-snapshot.sh      # Consistent Snapshot 테스트 실행
└── 05-consistent-snapshot.sql     # Consistent Snapshot SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **02-time-datatypes** - 간단한 데이터 타입부터 시작
3. **04-lag-lead-functions** - 윈도우 함수 기초 학습

#### 중급 사용자
1. **01-coalescingmergetree** - 테이블 엔진 최적화 이해
2. **03-bech32-encoding** - 인코딩 및 보안 개념
3. **05-consistent-snapshot** - 트랜잭션 및 일관성

#### 고급 사용자
- 모든 기능을 조합하여 실제 프로덕션 시나리오 구현
- EXPLAIN 명령으로 쿼리 실행 계획 분석
- 성능 벤치마킹 및 비교
- 실시간 데이터 파이프라인 설계

### 💡 기능 비교

#### CoalescingMergeTree vs ReplacingMergeTree

| 기능 | CoalescingMergeTree | ReplacingMergeTree |
|---------|---------------------|-------------------|
| 업데이트 방식 | Sign 컬럼 (-1, +1) | 버전 컬럼 |
| 병합 시점 | 자동 병합 | FINAL 쿼리 필요 |
| 성능 | 빈번한 업데이트에 적합 | 드문 업데이트에 적합 |
| 용도 | 메트릭, CDC | 마스터 데이터, 차원 테이블 |

#### Time vs DateTime

| 기능 | Time/Time64 | DateTime |
|---------|-------------|----------|
| 저장 내용 | 시간만 (자정 기준) | 날짜 + 시간 |
| 정밀도 | 초 or 마이크로초 | 초 |
| 용도 | 업무 시간, 일정 | 타임스탬프, 이벤트 |
| 저장 크기 | 작음 | 큼 |

### 🆕 25.6의 새로운 기능

- **`CoalescingMergeTree`** — engine for sparse updates ([#79344](https://github.com/ClickHouse/ClickHouse/pull/79344))
- **`Time` / `Time64` data types** — time-of-day types with cast functions ([#81217](https://github.com/ClickHouse/ClickHouse/pull/81217))
- **Bech32 encoding functions** — `bech32Encode` / `bech32Decode` ([#80239](https://github.com/ClickHouse/ClickHouse/pull/80239))
- **`lag` / `lead` window functions** — SQL-standard offset windows ([#82108](https://github.com/ClickHouse/ClickHouse/pull/82108))
- **Consistent storage snapshots across subqueries** — shared snapshot setting ([#79471](https://github.com/ClickHouse/ClickHouse/pull/79471))
- **Writing to the `Merge` table engine** — `Merge` is no longer read-only ([#77484](https://github.com/ClickHouse/ClickHouse/pull/77484))
- **Map value functions** — `mapContainsValues`, `mapExtractValuesLike` and friends ([#78171](https://github.com/ClickHouse/ClickHouse/pull/78171))
- **Query slot scheduling for workloads** — workload-level concurrency control ([#78415](https://github.com/ClickHouse/ClickHouse/pull/78415))
- **JSON columns in Parquet** — read and write ClickHouse JSON as Parquet JSON ([#79649](https://github.com/ClickHouse/ClickHouse/pull/79649))
- **`deltaLakeLocal`** — query filesystem-mounted Delta tables ([#79781](https://github.com/ClickHouse/ClickHouse/pull/79781))
- **WKB reader functions** — read Well-Known Binary geometries ([#80139](https://github.com/ClickHouse/ClickHouse/pull/80139))
- **`MultiPolygon` in `pointInPolygon`** — multi-polygon containment ([#79773](https://github.com/ClickHouse/ClickHouse/pull/79773))
- **`timeSeries*` helper functions** — time series operations ([#80590](https://github.com/ClickHouse/ClickHouse/pull/80590))
- **`USE DATABASE`** — standard database switching syntax ([#81307](https://github.com/ClickHouse/ClickHouse/pull/81307))
- **`system.codecs`** — introspect available compression codecs ([#81600](https://github.com/ClickHouse/ClickHouse/pull/81600))
- **chdig TUI** — bundled terminal UI for ClickHouse ([#79666](https://github.com/ClickHouse/ClickHouse/pull/79666))

### 🔍 추가 자료

- **Official Release Blog**: [ClickHouse 25.6 Release](https://clickhouse.com/blog/clickhouse-release-25-06)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다

### 🔒 보안 고려사항

**Bech32 인코딩 사용 시:**
- 체크섬이 포함되어 있지만 암호화는 아님
- 민감한 데이터는 추가 암호화 필요
- 공개 식별자로만 사용 권장

**CoalescingMergeTree 사용 시:**
- Sign 컬럼 관리에 주의
- 애플리케이션 레벨에서 일관성 보장 필요
- 동시성 제어 메커니즘 고려

### ⚡ 성능 팁

**CoalescingMergeTree:**
- 적절한 ORDER BY 키 설정으로 머지 효율 향상
- 파티션 전략으로 과거 데이터 관리
- Sign 필터링으로 읽기 성능 최적화

**Time64 데이터 타입:**
- 높은 정밀도가 필요한 경우만 Time64 사용
- 대부분의 경우 Time으로 충분
- 인덱스 및 파티션 키로 사용 가능

**lag/lead 함수:**
- 적절한 PARTITION BY로 윈도우 크기 제한
- ORDER BY 최적화로 정렬 비용 감소
- 큰 offset 값은 성능에 영향

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
