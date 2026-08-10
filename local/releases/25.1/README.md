# ClickHouse 25.1 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.1 new features. This directory focuses on verified and working features newly added in ClickHouse 25.1 (released 2025-02-07, the first release of 2025 with 15 new features, 36 performance optimizations and 77 bug fixes).

### 📋 Overview

ClickHouse 25.1 trims boilerplate off two everyday jobs. A table setting builds minmax skip indices on every suitable column, so a wide table no longer needs an `INDEX` clause per column. `Merge` tables stop breaking when the underlying schemas have drifted: a column whose type differs between tables now surfaces as a `Variant`. On the function side, `sequenceMatchEvents` returns the rows a funnel pattern matched rather than a yes/no.

### 🎯 Key Features

1. **Automatic MinMax Indices** — one table setting instead of an `INDEX` clause per column
2. **`Merge` Tables Unify Schemas as `Variant`** — schema drift becomes a type, not an error
3. **New Functions** — `sequenceMatchEvents`, `arrayNormalizedGini`, `currentQueryID`

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/25.1
./00-setup.sh

./01-auto-minmax-index.sh
./02-merge-variant-schema.sh
./03-new-functions.sh
```

### 📚 Feature Details

#### 1. Automatic MinMax Indices (01-auto-minmax-index)

**New Feature:** the MergeTree settings `add_minmax_index_for_numeric_columns` and `add_minmax_index_for_string_columns` build a minmax skip index on every column of that kind, named `auto_minmax_index_<column>`.

**Test Content:**
- A 500k-row table with and without the setting, side by side
- The generated index list from `system.data_skipping_indices`
- The separate switch for string columns
- `EXPLAIN indexes = 1` on a correlated column, showing the skip index engage
- The same query returning identical results either way
- An uncorrelated column where the index is built but prunes nothing
- What the indices cost on disk against the table itself
- The setting is create-time only — the explicit `ADD INDEX` + `MATERIALIZE INDEX` route for an existing table

**Key Learning Points:**
- The indices are named `auto_minmax_index_<column>` and appear in `system.data_skipping_indices` like any other
- Numeric and string columns are two separate settings; neither is on by default
- The setting is **read-only after creation** — `ALTER TABLE ... MODIFY SETTING` fails with `READONLY_SETTING`, so an existing table needs indices added explicitly
- An index is built per column regardless of whether it can help: on a column that cycles every few rows every granule holds every value, and nothing is pruned
- Index storage is small next to the data (≈1.2 KiB against ≈4 MiB here), which is what makes indexing everything reasonable

**Use Cases:**
- Wide fact tables where writing an `INDEX` clause per column is tedious
- Exploratory tables whose query patterns are not known yet
- Getting range-predicate pruning without picking winners in advance

---

#### 2. `Merge` Tables Unify Schemas as `Variant` (02-merge-variant-schema)

**New Feature:** when the `merge()` table function spans tables whose columns share a name but not a type, the column is exposed as a `Variant` of the types involved instead of failing.

**Test Content:**
- Three tables where `user_id` migrated from `UInt32` to `String`
- The merged view showing `Variant(String, UInt32)`
- `variantType()` and `variantElement()` to see and extract which alternative a row holds
- Filtering to only the legacy rows, then only the migrated rows
- Normalising back to one comparable key with `toString()`, then aggregating on it
- Columns that agree keeping their original type
- A `Merge` **engine** table following its declared schema instead, and why that differs
- `_table` showing which source each row came from

**Key Learning Points:**
- Only the conflicting column becomes a `Variant`; the rest keep their types
- `variantType(col)` names the alternative a row holds; `variantElement(col, 'Type')` extracts it and returns `NULL` for the others
- Casting the `Variant` to a common type gives one key usable for `GROUP BY` or a join
- The `merge()` **function** infers the `Variant`; a `Merge` **engine** table created `AS <table>` uses that declared schema and casts into it instead
- `_table` is the handle for attributing rows back to their source during a migration

**Use Cases:**
- Querying across a table that was rewritten mid-migration
- Union views over per-version or per-tenant tables whose schemas have drifted
- Auditing which rows still use a retired representation

---

#### 3. New Functions (03-new-functions)

**New Features:**
- `sequenceMatchEvents(pattern)(timestamp, cond1, ...)` — returns the timestamps of the events that satisfied a sequence pattern
- `arrayNormalizedGini(scores, labels)` — ranking quality as `(gini, perfect_gini, normalized_gini)`
- `currentQueryID()` / `current_query_id()` — the id of the running query

**Test Content:**
- A four-user funnel with complete, abandoned and out-of-order journeys
- `sequenceMatchEvents` returning the matched timestamps per user
- The same pattern through `sequenceMatch`, which only answers yes or no
- Deriving time-to-purchase from the matched events
- `arrayNormalizedGini` on a perfect, an inverted and a signal-free ranking
- Scoring two stored models and ranking them by normalized Gini
- `currentQueryID()` and its snake_case alias
- Carrying the query id into a result set

**Key Learning Points:**
- `sequenceMatchEvents` returns what it found even when the full pattern did not match — a partial journey yields a shorter array, so check `length()` before indexing
- The array positions line up with the pattern conditions, so `matched[1]` and `matched[3]` bracket the funnel
- `arrayNormalizedGini` returns a tuple; the third member is the normalized score, `1` for a perfect ranking and `-1` for a perfectly inverted one
- `currentQueryID()` lets a result carry the handle needed to find itself in `system.query_log`
- `generateSerialID`, also new in 25.1, is not covered here: it stores its counter in Keeper and returns `NO_ELEMENTS_IN_CONFIG` on a standalone server

**Use Cases:**
- Funnel analysis that needs the matched events, not just a match flag
- Comparing ranking models directly in SQL
- Correlating an exported result with its entry in the query log

---

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

#### Useful Commands

```bash
cd ../../oss-mac-setup
./status.sh
./client.sh 8123
docker logs clickhouse-25-1
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
25.1/
├── README.md                       # This document
├── 00-setup.sh                     # ClickHouse 25.1 installation script
├── 01-auto-minmax-index.sh         # Automatic minmax index runner
├── 01-auto-minmax-index.sql        # Automatic minmax index SQL
├── 02-merge-variant-schema.sh      # Merge/Variant runner
├── 02-merge-variant-schema.sql     # Merge/Variant SQL
├── 03-new-functions.sh             # New functions runner
└── 03-new-functions.sql            # New functions SQL
```

### 🆕 What's New in 25.1

- **Automatic minmax indices** — `add_minmax_index_for_numeric_columns` / `add_minmax_index_for_string_columns`
- **`Merge` tables unify differing column types** as `Variant`
- **`sequenceMatchEvents`** — the matched events of a sequence pattern
- **`arrayNormalizedGini`** — normalized Gini coefficient for ranking quality
- **`currentQueryID`** / **`current_query_id`** — id of the running query
- **`generateSerialID`** — distributed auto-increment counters backed by Keeper
- **`system.azure_queue`** system table
- **Faster parallel hash join** — two-level hash map in the build phase
- **Binary format confirmation** — prompts before writing a binary format to a terminal
- **Column name shortening** in pretty output formats

### 🔍 Additional Resources

- **Release Blog**: [ClickHouse Release 25.1](https://clickhouse.com/blog/clickhouse-release-25-01)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 25.1.8.25
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- `generateSerialID` needs a configured Keeper and is therefore not exercised by these labs


### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 25.1 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2025년 2월 7일 출시된 ClickHouse 25.1에서 검증된 작동 기능에 집중합니다. 25.1은 2025년 첫 릴리스로 신기능 15건, 성능 최적화 36건, 버그 수정 77건을 포함합니다.

### 📋 개요

ClickHouse 25.1은 일상적인 두 작업의 보일러플레이트를 걷어냅니다. 테이블 설정 하나로 적합한 모든 컬럼에 minmax 스킵 인덱스를 만들어, 넓은 테이블에 컬럼마다 `INDEX` 절을 쓸 필요가 없어집니다. 스키마가 달라진 테이블들을 `Merge`로 묶어도 더 이상 실패하지 않고, 타입이 다른 컬럼은 `Variant`로 노출됩니다. 함수 쪽에서는 `sequenceMatchEvents`가 퍼널 패턴의 매칭 여부가 아니라 **매칭된 행**을 돌려줍니다.

### 🎯 주요 기능

1. **자동 MinMax 인덱스** — 컬럼마다 `INDEX` 절을 쓰는 대신 테이블 설정 하나로
2. **`Merge` 테이블의 스키마 통합(`Variant`)** — 스키마 드리프트가 오류가 아닌 타입이 됨
3. **신규 함수** — `sequenceMatchEvents`, `arrayNormalizedGini`, `currentQueryID`

### 🚀 빠른 시작

```bash
cd local/releases/25.1
./00-setup.sh

./01-auto-minmax-index.sh
./02-merge-variant-schema.sh
./03-new-functions.sh
```

### 📚 기능 상세

#### 1. 자동 MinMax 인덱스

MergeTree 설정 `add_minmax_index_for_numeric_columns`와 `add_minmax_index_for_string_columns`가 해당 종류의 모든 컬럼에 `auto_minmax_index_<컬럼>` 이름으로 minmax 스킵 인덱스를 생성합니다.

**테스트 내용:**
- 설정 유무를 나란히 둔 50만 행 테이블
- `system.data_skipping_indices`에서 생성된 인덱스 목록
- 문자열 컬럼용 별도 스위치
- 상관관계가 있는 컬럼에 대한 `EXPLAIN indexes = 1` — 스킵 인덱스 동작 확인
- 양쪽 결과가 동일함을 확인
- 인덱스가 만들어져도 프루닝하지 못하는 비상관 컬럼
- 테이블 대비 인덱스의 디스크 비용
- 생성 시점 전용 설정임을 확인하고, 기존 테이블용 `ADD INDEX` + `MATERIALIZE INDEX` 경로 제시

**핵심 학습 포인트:**
- 인덱스 이름은 `auto_minmax_index_<컬럼>`이며 일반 인덱스처럼 `system.data_skipping_indices`에 나타납니다
- 숫자용·문자열용은 별개 설정이고 둘 다 기본값은 꺼짐입니다
- 이 설정은 **생성 후 읽기 전용**입니다 — `ALTER TABLE ... MODIFY SETTING`은 `READONLY_SETTING`으로 실패하므로 기존 테이블은 인덱스를 명시적으로 추가해야 합니다
- 도움이 되는지와 무관하게 컬럼마다 인덱스가 생깁니다. 값이 몇 행마다 순환하는 컬럼은 모든 granule이 모든 값을 담아 프루닝이 되지 않습니다
- 인덱스 저장 비용은 데이터에 비해 작습니다(여기서는 약 1.2 KiB 대 약 4 MiB) — 전부 인덱싱해도 괜찮은 이유입니다

#### 2. `Merge` 테이블의 `Variant` 스키마 통합

`merge()` 테이블 함수가 이름은 같고 타입은 다른 컬럼을 가진 테이블들을 묶을 때, 실패하는 대신 해당 컬럼을 관련 타입들의 `Variant`로 노출합니다.

**테스트 내용:**
- `user_id`가 `UInt32`에서 `String`으로 마이그레이션된 테이블 3개
- 병합 뷰에서 `Variant(String, UInt32)` 확인
- `variantType()`·`variantElement()`로 행이 가진 대안 확인 및 추출
- 레거시 행만, 그다음 마이그레이션된 행만 필터링
- `toString()`으로 비교 가능한 단일 키로 정규화한 뒤 집계
- 타입이 일치하는 컬럼은 원래 타입 유지
- `Merge` **엔진** 테이블은 선언된 스키마를 따른다는 차이
- `_table`로 각 행의 출처 확인

**핵심 학습 포인트:**
- 충돌하는 컬럼만 `Variant`가 되고 나머지는 타입을 유지합니다
- `variantType(col)`은 행이 가진 대안의 이름을, `variantElement(col, 'Type')`은 그 값을 반환하며 다른 대안이면 `NULL`입니다
- `Variant`를 공통 타입으로 캐스팅하면 `GROUP BY`나 조인에 쓸 수 있는 단일 키가 됩니다
- `Variant`를 추론하는 건 `merge()` **함수**입니다. `AS <테이블>`로 만든 `Merge` **엔진** 테이블은 선언된 스키마를 따르며 그 타입으로 캐스팅합니다
- 마이그레이션 중 행의 출처를 추적할 때는 `_table`이 유용합니다

#### 3. 신규 함수

- `sequenceMatchEvents(패턴)(타임스탬프, 조건1, ...)` — 시퀀스 패턴을 만족한 이벤트들의 타임스탬프 반환
- `arrayNormalizedGini(점수, 라벨)` — `(gini, 완전정렬 gini, 정규화 gini)` 형태의 랭킹 품질
- `currentQueryID()` / `current_query_id()` — 실행 중인 쿼리의 id

**테스트 내용:**
- 완주·이탈·순서 이탈이 섞인 4명의 퍼널 데이터
- 사용자별 매칭 타임스탬프를 반환하는 `sequenceMatchEvents`
- 예/아니오만 답하는 `sequenceMatch`와 비교
- 매칭된 이벤트로 구매까지 걸린 시간 계산
- 완전 정렬·역정렬·무신호 랭킹에 대한 `arrayNormalizedGini`
- 저장된 두 모델을 정규화 Gini로 채점·정렬
- `currentQueryID()`와 snake_case 별칭
- 결과 집합에 쿼리 id 실어 보내기

**핵심 학습 포인트:**
- `sequenceMatchEvents`는 전체 패턴이 매칭되지 않아도 찾은 것까지 반환합니다 — 부분 여정은 더 짧은 배열이 되므로 인덱싱 전에 `length()`를 확인하세요
- 배열 위치는 패턴 조건과 대응하므로 `matched[1]`과 `matched[3]`이 퍼널의 양 끝이 됩니다
- `arrayNormalizedGini`는 튜플을 반환하며 세 번째 값이 정규화 점수입니다. 완전 정렬이면 `1`, 완전 역정렬이면 `-1`입니다
- `currentQueryID()`로 결과가 `system.query_log`에서 자신을 찾을 수 있는 핸들을 지니게 됩니다
- 같은 25.1 신규 기능인 `generateSerialID`는 여기서 다루지 않습니다 — 카운터를 Keeper에 저장하므로 단독 서버에서는 `NO_ELEMENTS_IN_CONFIG`가 발생합니다

### 🆕 25.1의 새로운 기능

- **자동 minmax 인덱스** — `add_minmax_index_for_numeric_columns` / `add_minmax_index_for_string_columns`
- **`Merge` 테이블의 타입 불일치 컬럼을 `Variant`로 통합**
- **`sequenceMatchEvents`** — 시퀀스 패턴에 매칭된 이벤트
- **`arrayNormalizedGini`** — 랭킹 품질용 정규화 Gini 계수
- **`currentQueryID`** / **`current_query_id`** — 실행 중인 쿼리 id
- **`generateSerialID`** — Keeper 기반 분산 auto-increment 카운터
- **`system.azure_queue`** 시스템 테이블
- **병렬 해시 조인 속도 개선** — build 단계의 2단계 해시 맵
- **바이너리 포맷 확인 프롬프트** — 터미널에 바이너리 포맷 출력 전 확인
- **Pretty 출력 포맷의 긴 컬럼명 축약**

### 🔍 추가 자료

- **Release Blog**: [ClickHouse Release 25.1](https://clickhouse.com/blog/clickhouse-release-25-01)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)

### 📝 참고사항

- 모든 기능은 ClickHouse 25.1.8.25에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- `generateSerialID`는 Keeper 설정이 필요해 이 랩에서는 다루지 않습니다


### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**
