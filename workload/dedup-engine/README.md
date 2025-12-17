# ClickHouse Deduplication Test Suite

ClickHouse의 다양한 테이블 엔진과 Insert 패턴별 Deduplication 효과를 테스트하는 실행 가능한 테스트 스위트입니다.

## 📋 테스트 개요

### Phase 1: Engine 비교 테스트
- **목적**: 동일한 중복 데이터에 대해 각 Table Engine의 deduplication 동작 방식과 효과 비교
- **테스트 대상**:
  - MergeTree (Baseline)
  - ReplacingMergeTree
  - CollapsingMergeTree
  - AggregatingMergeTree

### Phase 2: Insert 패턴별 성능 테스트
- **목적**: Row-by-row vs Batch insert의 성능 차이 측정
- **테스트 패턴**:
  - Row-by-row insert
  - Micro-batch insert (100 rows)
  - Batch insert (10,000 rows)
  - Async insert

### Phase 3: 권장 아키텍처 검증
- **목적**: Landing → Main → Refreshable MV 아키텍처 검증
- **구조**:
  ```
  [Landing Table] → [Main Table] → [Refreshable MV]
  (MergeTree+TTL)   (ReplacingMT)   (Aggregation)
  ```

## 🚀 빠른 시작

### 1. 환경 설정

#### 필수 요구사항
- Python 3.7+
- ClickHouse Cloud 또는 Self-managed 인스턴스

#### 패키지 설치
```bash
pip3 install clickhouse-connect python-dotenv
```

### 2. 연결 정보 설정

`.env` 파일을 생성하고 ClickHouse 연결 정보를 입력합니다:

```bash
CH_HOST=your-host.clickhouse.cloud
CH_PORT=8443
CH_USERNAME=default
CH_PASSWORD=your-password
CH_DATABASE=default
CH_SECURE=true
```

### 3. 테스트 실행

#### 방법 1: 대화형 모드
```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/workload/dedup-engine
python3 run_all_tests.py
```

메뉴가 표시되면 실행할 테스트를 선택합니다.

#### 방법 2: CLI 모드
```bash
# Phase 1만 실행
python3 run_all_tests.py 1

# Phase 2만 실행
python3 run_all_tests.py 2

# Phase 3만 실행
python3 run_all_tests.py 3

# 전체 테스트 실행
python3 run_all_tests.py all
```

#### 방법 3: 개별 실행
```bash
# Phase 1 실행
python3 phase1_engine_comparison.py

# Phase 2 실행
python3 phase2_insert_patterns.py

# Phase 3 실행
python3 phase3_architecture.py
```

## 📊 예상 결과

### Phase 1: Engine 비교

```
Engine        | Raw Count | Dedup Count | After OPTIMIZE | Success
---------------------------------------------------------------------
MergeTree     | 13,000    | 10,000      | 13,000         | ❌
ReplacingMT   | 10,000    | 10,000      | 10,000         | ✅
CollapsingMT  | 10,000    | 10,000      | 10,000         | ✅
AggregatingMT | 10,000    | 10,000      | 10,000         | ✅
```

### Phase 2: Insert 패턴

```
Method       | Records | Time (s) | Rate (rows/s)
--------------------------------------------------
row_by_row   | 1,000   | ~60      | ~16
micro_batch  | 10,000  | ~8       | ~1,200
batch        | 10,000  | ~0.3     | ~35,000
async_insert | 1,000   | ~10      | ~100
```

**성능 개선**:
- Batch insert가 row-by-row 대비 **2,000배 이상** 빠름
- Micro-batch도 **70배 이상** 성능 개선

### Phase 3: 아키텍처 검증

```
항목           | 레코드 수 | 비고
------------------------------------
Landing        | 13,000    | 원본 데이터
Main (Raw)     | 13,000    | MV로 전달
Main (FINAL)   | 10,000    | Dedup 후
Hourly Agg     | N         | Refreshable MV
```

## 📁 파일 구조

```
dedup-engine/
├── .env                          # 연결 정보 (생성 필요)
├── .gitignore
├── config.py                     # 설정
├── utils.py                      # 공통 유틸리티
├── phase1_engine_comparison.py   # Phase 1 테스트
├── phase2_insert_patterns.py     # Phase 2 테스트
├── phase3_architecture.py        # Phase 3 테스트
├── run_all_tests.py              # 통합 실행 스크립트
├── README.md                     # 본 문서
└── dedup_test_plan.md            # 전체 테스트 계획서
```

## 🔧 설정 커스터마이징

`config.py` 파일에서 테스트 데이터 설정을 변경할 수 있습니다:

```python
@dataclass
class TestConfig:
    # 테스트 데이터 설정
    total_unique_records: int = 10000      # Unique 레코드 수
    duplicate_rate: float = 0.3            # 중복 비율 (30%)
    account_cardinality: int = 1000        # Account 종류
    product_cardinality: int = 500         # Product 종류
```

## 🧹 정리 (Cleanup)

테스트 후 생성된 테이블을 정리하려면:

```sql
-- ClickHouse 클라이언트에서 실행
DROP DATABASE IF EXISTS dedup;
```

또는 개별 테이블 삭제:

```sql
-- Phase 1
DROP TABLE IF EXISTS dedup.p1_baseline;
DROP TABLE IF EXISTS dedup.p1_replacing;
DROP TABLE IF EXISTS dedup.p1_collapsing;
DROP TABLE IF EXISTS dedup.p1_aggregating;

-- Phase 2
DROP TABLE IF EXISTS dedup.p2_row_by_row;
DROP TABLE IF EXISTS dedup.p2_micro_batch;
DROP TABLE IF EXISTS dedup.p2_batch;
DROP TABLE IF EXISTS dedup.p2_async_insert;

-- Phase 3
DROP VIEW IF EXISTS dedup.p3_hourly_agg;
DROP VIEW IF EXISTS dedup.p3_landing_to_main_mv;
DROP TABLE IF EXISTS dedup.p3_main;
DROP TABLE IF EXISTS dedup.p3_landing;
```

## 📝 주요 발견사항

### 1. Engine 선택
- **ReplacingMergeTree**: ✅ 추천
  - 구현이 간단하고 효과적
  - FINAL 키워드로 중복 제거된 데이터 조회

- **CollapsingMergeTree**: ⚠️ 조건부
  - Sign 관리가 복잡
  - Update/Delete 시나리오에 적합

- **AggregatingMergeTree**: ⚠️ 조건부
  - 집계 시나리오에 적합
  - SimpleAggregateFunction 필요

### 2. Insert 패턴
- **Batch Insert 강력 권장**
  - 2,000배 이상의 성능 개선
  - 네트워크 오버헤드 최소화

- **Async Insert**
  - Row-by-row보다 5배 빠름
  - 하지만 Batch에 비해서는 느림

### 3. 권장 아키텍처
```
[App] → [Landing + TTL] → [ReplacingMT] → [Refreshable MV]
```
- Landing 테이블로 빠른 insert
- ReplacingMergeTree로 자동 dedup
- TTL로 자동 정리
- Refreshable MV로 정확한 집계

## 📚 참고 문서

- [ReplacingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Refreshable Materialized Views](https://clickhouse.com/docs/en/materialized-view/refreshable-materialized-view)
- [Async Insert](https://clickhouse.com/docs/en/cloud/bestpractices/asynchronous-inserts)
- [TTL](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-ttl)

## 🐛 문제 해결

### 연결 실패
```
✗ ClickHouse 연결 실패: Database dedup does not exist
```
→ `.env` 파일의 `CH_DATABASE`를 `default`로 설정

### 권한 오류
```
DB::Exception: Not enough privileges
```
→ 사용자에게 데이터베이스 생성 권한 필요

### Refreshable MV 오류
```
Refreshable materialized views are not supported
```
→ ClickHouse 버전이 23.8 이상인지 확인

## 📧 문의

테스트 관련 문의사항은 ClickHouse Solutions Team에 연락주세요.
