# ClickHouse 25.3 LTS New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.3 new features. This directory focuses on verified and working features newly added in ClickHouse 25.3 (released 2025-03-20, the first LTS release of 2025).

### 📋 Overview

ClickHouse 25.3 is an LTS release that adds two tools for making a decision instead of guessing at one, plus a batch of new functions. The query condition cache remembers which granules a filter could not match, so repeating that filter reads less. `estimateCompressionRatio` answers "which codec should this column use" from a `SELECT` rather than a write-and-measure loop.

### 🎯 Key Features

1. **New Functions** — `arraySymmetricDifference`, `keccak256`, `firstNonDefault`, `compareSubstrings`, Iceberg transform helpers
2. **Query Condition Cache** — `use_query_condition_cache` and `system.query_condition_cache`
3. **`estimateCompressionRatio`** — estimate a codec's effect without writing the data

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/25.3
./00-setup.sh

./01-new-functions.sh
./02-query-condition-cache.sh
./03-estimate-compression-ratio.sh
```

### 📚 Feature Details

#### 1. New Functions (01-new-functions)

**New Features:** `arraySymmetricDifference`, `keccak256`, `firstNonDefault`, `compareSubstrings`, `icebergTruncate`, `toYearNumSinceEpoch`, `toMonthNumSinceEpoch` — the function surface this release added, confirmed by diffing `system.functions` against 25.2.

**Test Content:**
- `arraySymmetricDifference` on two and three arrays
- Contrasted with `arrayIntersect` and a distinct concat
- A permission-drift query: which grants only one role has
- `keccak256` on literals, and its empty-input hash
- Hashing a column and grouping by the hash
- `firstNonDefault` for `0`/`''`-as-missing data
- A phone-number fallback chain across three columns
- `compareSubstrings` comparing slices without materialising them
- Iceberg transform helpers and a month-partition rollup

**Key Learning Points:**
- `arraySymmetricDifference` returns elements not present in **all** arguments, so with three or more arrays it is not the pairwise difference — and the result order is unspecified, so sort before comparing
- `keccak256` is Keccak-256, the pre-standard variant Ethereum uses; it is not the finalised SHA3-256 and the two produce different digests
- `firstNonDefault` keys off each type's default value, which makes it the right tool when `0` and `''` mean "missing" and `NULL` was never used
- `compareSubstrings(a, b, offset_a, offset_b, length)` uses 0-based offsets and returns `-1`/`0`/`1`
- `toYearNumSinceEpoch` / `toMonthNumSinceEpoch` count from 1970, which is exactly what an Iceberg year/month partition value holds

**Use Cases:**
- Diffing permission or feature sets between roles or tenants
- Blockchain address and event-topic hashing in SQL
- Fallback chains over columns where empty means absent
- Computing Iceberg partition values without leaving ClickHouse

---

#### 2. Query Condition Cache (02-query-condition-cache)

**New Feature:** with `use_query_condition_cache = 1`, ClickHouse records per granule that a `WHERE` condition matched nothing. A later query with the same condition skips those granules instead of re-evaluating them. `system.query_condition_cache` exposes the entries.

**Test Content:**
- A 3M-row log table where `status = 500` occupies a narrow id range
- The setting and its default
- `SYSTEM DROP QUERY CONDITION CACHE`, then an empty cache
- A first run populating three entries
- The cache contents: one row per part and condition, with a mark bitmap
- Repeating the condition with a different projection and a different aggregate
- Cached and uncached results proven identical
- Separate conditions creating separate entries
- A predicate that nearly every granule satisfies, where there is nothing to skip
- Dropping the cache, and an insert afterwards

**Key Learning Points:**
- This is **not** a result cache: it caches the negative answer per granule, so a later query with the same predicate but different columns or aggregates still benefits
- The setting is **off by default** and applies per query or per profile
- Entries are keyed by `(part, condition hash)` — `system.query_condition_cache` shows `part_name`, `key_hash` and a `matching_marks` bitmap
- Selectivity decides the value: a predicate matching a narrow id range prunes almost everything, while `status = 200` matching nearly every granule has nothing to record
- New parts are not covered by existing entries, so an insert cannot make the cache stale

**Use Cases:**
- Dashboards that re-run the same filter with different aggregates
- Repeated needle-in-haystack lookups over an append-only log table
- Any workload where the same `WHERE` clause appears across many queries

---

#### 3. `estimateCompressionRatio` (03-estimate-compression-ratio)

**New Feature:** an aggregate that estimates a column's compression ratio, either under the default codec or under a codec you name: `estimateCompressionRatio('Delta, ZSTD')(col)`.

**Test Content:**
- One table with a constant column, a low-cardinality column, an incrementing column and a hash column
- Default-codec ratios for each
- `LZ4` versus `ZSTD` versus `ZSTD(9)` on the same column
- `Delta` and `DoubleDelta` in front of `ZSTD` on a sequence
- The same codecs on non-sequential data, where they buy nothing
- A monotonic `DateTime` column
- The estimate checked against a real part written with `CODEC(Delta, ZSTD)`
- Every column ranked by ratio in one query
- The estimate from all rows versus from a 50k sample

**Key Learning Points:**
- The parametric form takes the codec pipeline as a string, so `Delta, ZSTD` and `DoubleDelta, ZSTD` can be compared directly
- Codec choice is data-shaped: on this lab's incrementing column `ZSTD` alone estimates ≈8, `Delta, ZSTD` ≈79 and `DoubleDelta, ZSTD` ≈6579, while on a hash column all of them sit at ≈1
- **The estimate is optimistic.** The same `Delta, ZSTD` column estimated ≈79 here but measured 3.6 once written and merged, so treat the numbers as a ranking between codecs rather than a size prediction
- A 50k sample gave 7.8 against 7.9 for all 500k rows — sampling is enough to choose a codec
- Ratios near 1 mean the column is already incompressible; no codec will rescue it

**Use Cases:**
- Choosing a codec per column before a large backfill
- Auditing an existing schema for columns that would benefit from `Delta`/`DoubleDelta`
- Justifying a codec change with numbers rather than intuition

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
docker logs clickhouse-25-3
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
25.3/
├── README.md                            # This document
├── 00-setup.sh                          # ClickHouse 25.3 installation script
├── 01-new-functions.sh                  # New functions runner
├── 01-new-functions.sql                 # New functions SQL
├── 02-query-condition-cache.sh          # Query condition cache runner
├── 02-query-condition-cache.sql         # Query condition cache SQL
├── 03-estimate-compression-ratio.sh     # Compression estimate runner
└── 03-estimate-compression-ratio.sql    # Compression estimate SQL
```

### 🆕 What's New in 25.3 LTS

- **Query condition cache** — `use_query_condition_cache`, `system.query_condition_cache`
- **`estimateCompressionRatio`** aggregate ([#76661](https://github.com/ClickHouse/ClickHouse/pull/76661))
- **`arraySymmetricDifference`** ([#76231](https://github.com/ClickHouse/ClickHouse/pull/76231))
- **`keccak256`** for blockchain workloads ([#76669](https://github.com/ClickHouse/ClickHouse/pull/76669))
- **`firstNonDefault`** and **`compareSubstrings`**
- **Iceberg transforms** — `icebergTruncate`, `toYearNumSinceEpoch`, `toMonthNumSinceEpoch` ([#77403](https://github.com/ClickHouse/ClickHouse/pull/77403))
- **`JSON`, `Dynamic` and `Variant` are production-ready** ([#77785](https://github.com/ClickHouse/ClickHouse/pull/77785))
- **Userspace page cache** for remote virtual filesystems ([#70509](https://github.com/ClickHouse/ClickHouse/pull/70509))
- **`concurrent_threads_scheduler`** server setting ([#75949](https://github.com/ClickHouse/ClickHouse/pull/75949))
- **`system.histogram_metrics`** system table
- **Profile events** `FilterTransformPassedRows` / `FilterTransformPassedBytes` ([#76662](https://github.com/ClickHouse/ClickHouse/pull/76662))
- **Header forwarding to external HTTP authenticators** ([#77054](https://github.com/ClickHouse/ClickHouse/pull/77054))

### 🔍 Additional Resources

- **Changelog**: [ClickHouse 25.3](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 25.3.14.14
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- The changelog also lists low-cardinality decimal support, but `LowCardinality(Decimal(10, 2))` is still rejected on 25.3.14 with `ILLEGAL_TYPE_OF_ARGUMENT`, so it is not exercised here


### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 25.3 LTS 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2025년 3월 20일 출시된 ClickHouse 25.3에서 검증된 작동 기능에 집중합니다. 2025년 첫 LTS 릴리스입니다.

### 📋 개요

ClickHouse 25.3은 "추측 대신 판단"을 돕는 두 가지 도구와 다수의 신규 함수를 담은 LTS 릴리스입니다. 쿼리 조건 캐시는 필터가 매칭될 수 없는 granule을 기억해 같은 필터의 재실행 시 읽는 양을 줄입니다. `estimateCompressionRatio`는 "이 컬럼에 어떤 코덱을 쓸까"를 쓰고-측정하는 반복 대신 `SELECT` 한 번으로 답합니다.

### 🎯 주요 기능

1. **신규 함수** — `arraySymmetricDifference`, `keccak256`, `firstNonDefault`, `compareSubstrings`, Iceberg 변환 헬퍼
2. **쿼리 조건 캐시** — `use_query_condition_cache`, `system.query_condition_cache`
3. **`estimateCompressionRatio`** — 데이터를 쓰지 않고 코덱 효과 추정

### 🚀 빠른 시작

```bash
cd local/releases/25.3
./00-setup.sh

./01-new-functions.sh
./02-query-condition-cache.sh
./03-estimate-compression-ratio.sh
```

### 📚 기능 상세

#### 1. 신규 함수

`arraySymmetricDifference`, `keccak256`, `firstNonDefault`, `compareSubstrings`, `icebergTruncate`, `toYearNumSinceEpoch`, `toMonthNumSinceEpoch` — 25.2 대비 `system.functions` 차이로 확인한 이번 릴리스의 함수 추가분입니다.

**테스트 내용:**
- 배열 2개·3개에 대한 `arraySymmetricDifference`
- `arrayIntersect`, distinct concat과의 대비
- 권한 드리프트 쿼리: 한쪽 롤에만 있는 권한
- 리터럴에 대한 `keccak256`과 빈 입력 해시
- 컬럼 해싱 및 해시 기준 그룹화
- `0`/`''`을 결측으로 쓰는 데이터에 대한 `firstNonDefault`
- 컬럼 3개에 걸친 전화번호 폴백 체인
- 부분 문자열을 만들지 않고 비교하는 `compareSubstrings`
- Iceberg 변환 헬퍼와 월 파티션 집계

**핵심 학습 포인트:**
- `arraySymmetricDifference`는 **모든** 인자에 없는 원소를 반환하므로 배열이 3개 이상이면 쌍별 차집합이 아닙니다. 결과 순서도 보장되지 않으니 비교 전에 정렬하세요
- `keccak256`은 이더리움이 쓰는 표준화 이전 Keccak-256이며, 확정된 SHA3-256과 다른 다이제스트를 만듭니다
- `firstNonDefault`는 타입별 기본값을 기준으로 하므로, `NULL` 없이 `0`과 `''`이 "없음"을 뜻하는 데이터에 적합합니다
- `compareSubstrings(a, b, offset_a, offset_b, length)`의 오프셋은 0 기반이며 `-1`/`0`/`1`을 반환합니다
- `toYearNumSinceEpoch` / `toMonthNumSinceEpoch`는 1970년 기준 카운트로, Iceberg의 연/월 파티션 값과 동일합니다

#### 2. 쿼리 조건 캐시

`use_query_condition_cache = 1`이면 ClickHouse가 `WHERE` 조건이 아무것도 매칭하지 못한 granule을 기록합니다. 이후 같은 조건의 쿼리는 그 granule을 재평가하지 않고 건너뜁니다. `system.query_condition_cache`에서 항목을 확인할 수 있습니다.

**테스트 내용:**
- `status = 500`이 좁은 id 구간에 몰린 300만 행 로그 테이블
- 설정과 기본값
- `SYSTEM DROP QUERY CONDITION CACHE` 후 빈 캐시 확인
- 첫 실행으로 항목 3개 생성
- 캐시 내용: 파트·조건별 한 행과 mark 비트맵
- 다른 프로젝션·다른 집계로 같은 조건 반복
- 캐시 사용/미사용 결과가 동일함을 증명
- 서로 다른 조건이 별도 항목을 만드는지 확인
- 거의 모든 granule이 만족하는 조건 — 건너뛸 것이 없는 경우
- 캐시 드롭과 이후 INSERT

**핵심 학습 포인트:**
- 결과 캐시가 **아닙니다**. granule 단위의 부정 답변을 캐시하므로, 같은 조건에 컬럼이나 집계가 달라도 이득을 봅니다
- 기본값은 **꺼짐**이며 쿼리 또는 프로파일 단위로 적용합니다
- 항목 키는 `(파트, 조건 해시)`이고 `system.query_condition_cache`에 `part_name`·`key_hash`·`matching_marks` 비트맵이 보입니다
- 선택도가 가치를 결정합니다. 좁은 id 구간을 겨냥한 조건은 대부분을 잘라내지만, 거의 모든 granule이 만족하는 `status = 200`은 기록할 게 없습니다
- 새 파트는 기존 항목의 적용 대상이 아니므로 INSERT로 캐시가 낡을 수 없습니다

#### 3. `estimateCompressionRatio`

기본 코덱 또는 지정한 코덱 기준으로 컬럼의 압축률을 추정하는 집계 함수입니다: `estimateCompressionRatio('Delta, ZSTD')(col)`.

**테스트 내용:**
- 상수 컬럼·저카디널리티 컬럼·증가 컬럼·해시 컬럼을 가진 테이블
- 각 컬럼의 기본 코덱 압축률
- 같은 컬럼에 대한 `LZ4` vs `ZSTD` vs `ZSTD(9)`
- 시퀀스에 대한 `Delta`·`DoubleDelta` + `ZSTD`
- 비순차 데이터에 같은 코덱을 적용했을 때 이득이 없음을 확인
- 단조 증가 `DateTime` 컬럼
- `CODEC(Delta, ZSTD)`로 실제 기록한 파트와 추정치 비교
- 한 쿼리로 전 컬럼 압축률 순위
- 전체 행 vs 5만 행 샘플 추정 비교

**핵심 학습 포인트:**
- 파라메트릭 형태는 코덱 파이프라인을 문자열로 받으므로 `Delta, ZSTD`와 `DoubleDelta, ZSTD`를 바로 비교할 수 있습니다
- 코덱 선택은 데이터 모양에 달렸습니다. 이 랩의 증가 컬럼에서 `ZSTD` 단독은 약 8, `Delta, ZSTD`는 약 79, `DoubleDelta, ZSTD`는 약 6579인 반면, 해시 컬럼에서는 모두 약 1입니다
- **추정치는 낙관적입니다.** 같은 `Delta, ZSTD` 컬럼이 여기서는 약 79로 추정됐지만 실제로 기록·머지된 뒤에는 3.6이었습니다. 크기 예측이 아니라 코덱 간 순위로 쓰세요
- 5만 행 샘플이 7.8, 전체 50만 행이 7.9였습니다 — 코덱 선택에는 샘플로 충분합니다
- 압축률이 1에 가깝다면 이미 압축 불가능한 컬럼이며 어떤 코덱도 구제하지 못합니다

### 🆕 25.3 LTS의 새로운 기능

- **쿼리 조건 캐시** — `use_query_condition_cache`, `system.query_condition_cache`
- **`estimateCompressionRatio`** 집계 함수 ([#76661](https://github.com/ClickHouse/ClickHouse/pull/76661))
- **`arraySymmetricDifference`** ([#76231](https://github.com/ClickHouse/ClickHouse/pull/76231))
- **`keccak256`** — 블록체인 워크로드용 ([#76669](https://github.com/ClickHouse/ClickHouse/pull/76669))
- **`firstNonDefault`**, **`compareSubstrings`**
- **Iceberg 변환** — `icebergTruncate`, `toYearNumSinceEpoch`, `toMonthNumSinceEpoch` ([#77403](https://github.com/ClickHouse/ClickHouse/pull/77403))
- **`JSON`·`Dynamic`·`Variant` 정식 지원(production-ready)** ([#77785](https://github.com/ClickHouse/ClickHouse/pull/77785))
- **유저스페이스 페이지 캐시** — 원격 가상 파일시스템용 ([#70509](https://github.com/ClickHouse/ClickHouse/pull/70509))
- **`concurrent_threads_scheduler`** 서버 설정 ([#75949](https://github.com/ClickHouse/ClickHouse/pull/75949))
- **`system.histogram_metrics`** 시스템 테이블
- **프로파일 이벤트** `FilterTransformPassedRows` / `FilterTransformPassedBytes` ([#76662](https://github.com/ClickHouse/ClickHouse/pull/76662))
- **외부 HTTP 인증기로의 헤더 전달** ([#77054](https://github.com/ClickHouse/ClickHouse/pull/77054))

### 🔍 추가 자료

- **Changelog**: [ClickHouse 25.3](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse 공식 문서**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 참고사항

- 모든 기능은 ClickHouse 25.3.14.14에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- changelog에는 low-cardinality decimal 지원도 있지만, 25.3.14에서 `LowCardinality(Decimal(10, 2))`는 여전히 `ILLEGAL_TYPE_OF_ARGUMENT`로 거부되어 여기서는 다루지 않습니다


### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**
