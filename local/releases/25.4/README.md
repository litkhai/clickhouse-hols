# ClickHouse 25.4 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.4 new features. This directory focuses on verified and working features newly added in ClickHouse 25.4 (released 2025-04-30).

### 📋 Overview

ClickHouse 25.4 is a release about comparing things. Levenshtein distance is lifted from characters to array elements, so two user journeys can be compared step by step. `sparseGrams` derives gram boundaries from the data instead of a fixed `n`, which makes near-duplicate detection work across strings of different lengths. And `hasAll()` learned to use token skip indices, so array-containment filters can prune.

### 🎯 Key Features

1. **Array Distance and Similarity** — `arrayLevenshteinDistance`, `arrayLevenshteinDistanceWeighted`, `arraySimilarity`
2. **`sparseGrams`** — data-derived n-grams, plus `hasAll()` using token indices
3. **`toInterval` and Editable Database Comments**

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/25.4
./00-setup.sh

./01-array-distance-functions.sh
./02-sparsegrams.sh
./03-tointerval-and-db-comments.sh
```

### 📚 Feature Details

#### 1. Array Distance and Similarity (01-array-distance-functions)

**New Feature:** `arrayLevenshteinDistance(lhs, rhs)`, `arrayLevenshteinDistanceWeighted(lhs, rhs, lhs_weights, rhs_weights)` and `arraySimilarity(...)` compute edit distance where the unit of edit is an array element rather than a character. ([#77187](https://github.com/ClickHouse/ClickHouse/pull/77187))

**Test Content:**
- Substitutions, insertions and deleting everything
- The element-wise nature shown against `editDistance` on the same pair
- Five session paths measured against a canonical happy path
- Pairwise distances across all sessions, grouped
- The weighted form, where each element carries a cost
- Weighting so that losing a checkout costs more than losing a blog visit
- `arraySimilarity` normalising the weighted distance into 0..1
- Sessions ranked by similarity
- Keeping weight arrays aligned with their value arrays

**Key Learning Points:**
- Elements are atomic: `['home','checkout']` versus `['home','checkout_v2']` is **one** edit, while `editDistance` on those strings reports three
- The weighted form takes four arrays — values and weights for each side — and every weight array must match its value array's length, which `arrayMap(x -> 1.0, arr)` guarantees
- `arraySimilarity` returns 1 for identical arrays and 0 when nothing lines up, so it sorts naturally as a ranking score
- Unweighted distance counts edits; weighted distance counts *cost*, so the two orderings can disagree — in this lab one substitution is distance 1 but weighted distance 7

**Use Cases:**
- Clustering user journeys or clickstreams by shape
- Comparing pipeline or workflow step sequences
- Fuzzy matching over tokenised text where the token, not the character, is the unit

---

#### 2. `sparseGrams` (02-sparsegrams)

**New Features:** `sparseGrams`, `sparseGramsHashes` and their `UTF8` variants produce variable-length grams whose boundaries come from the data. Separately, `hasAll()` now consults `tokenbf_v1` and `ngrambf_v1` skip indices. ([#78176](https://github.com/ClickHouse/ClickHouse/pull/78176), [#77662](https://github.com/ClickHouse/ClickHouse/pull/77662))

**Test Content:**
- The grams produced for a short string, and their varying lengths
- Fixed `ngrams(s, 3)` next to `sparseGrams` on the same input
- The hashed form, and its determinism
- Byte versus character behaviour on Korean text
- Near-duplicate detection: shared gram counts across three documents
- A Jaccard-style similarity built from gram overlap
- `hasAll()` against a `tokenbf_v1` index on an `Array(String)` column
- `EXPLAIN indexes = 1` for a tag present in every granule versus one confined to a narrow range
- Identical results with and without the skip index

**Key Learning Points:**
- Gram lengths vary — this lab's 11-character string yields grams from 3 to 8 characters, 17 of them, against 9 fixed trigrams
- `sparseGramsHashes` is the form to store or index: fixed-width integers instead of substrings
- The plain functions are byte-oriented; on Korean text `sparseGrams` produced 65 grams where `sparseGramsUTF8` produced 14, so use the UTF8 variants for non-ASCII
- Two sentences differing by one word shared 67 grams and scored 0.65 Jaccard, while an unrelated sentence scored 0.005
- `hasAll()` consulting the index does not mean it prunes: a tag present in every granule still reads 24/24, while a clustered tag reads 1/24
- Results are identical with `use_skip_indexes = 0`, so the index is purely an optimisation

**Use Cases:**
- Near-duplicate and plagiarism detection over documents
- Fuzzy joins keyed on gram overlap
- Tag-containment filters that need to prune rather than scan

---

#### 3. `toInterval` and Database Comments (03-tointerval-and-db-comments)

**New Features:** `toInterval(value, unit)` is the function form of the `INTERVAL` keyword ([#78723](https://github.com/ClickHouse/ClickHouse/pull/78723)), and `ALTER DATABASE ... MODIFY COMMENT` makes a database comment editable after creation ([#75622](https://github.com/ClickHouse/ClickHouse/pull/75622)).

**Test Content:**
- `toInterval` for day, hour and minute
- Date arithmetic with it, including a month step
- Proof it matches the `INTERVAL` keyword exactly
- The amount supplied by a column
- A retention table with a per-dataset unit, resolved with `multiIf`
- Expired-row counts per dataset from that table
- The full unit vocabulary, second through year
- `CREATE DATABASE ... COMMENT`, then `ALTER DATABASE ... MODIFY COMMENT`
- Searching `system.databases` by comment, and clearing one

**Key Learning Points:**
- The **value** may be any expression, but the **unit must be a constant string** — `toInterval(n, unit_column)` fails with `ILLEGAL_TYPE_OF_ARGUMENT`
- For a genuinely per-row unit, branch with `multiIf` and give each branch its own constant
- Branch on the resulting **timestamp**, not on the interval: intervals of different units have no common type and `multiIf` over them fails with `NO_COMMON_TYPE`
- Database comments are queryable metadata in `system.databases`, so `WHERE comment ILIKE ...` turns them into a searchable catalogue
- Setting the comment to `''` clears it

**Use Cases:**
- Retention and TTL logic driven by a configuration table
- Building interval arithmetic in generated SQL
- Recording ownership or purpose on a database and keeping it current

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
docker logs clickhouse-25-4
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
25.4/
├── README.md                             # This document
├── 00-setup.sh                           # ClickHouse 25.4 installation script
├── 01-array-distance-functions.sh        # Array distance runner
├── 01-array-distance-functions.sql       # Array distance SQL
├── 02-sparsegrams.sh                     # sparseGrams runner
├── 02-sparsegrams.sql                    # sparseGrams SQL
├── 03-tointerval-and-db-comments.sh      # toInterval / DB comments runner
└── 03-tointerval-and-db-comments.sql     # toInterval / DB comments SQL
```

### 🆕 What's New in 25.4

- **`arrayLevenshteinDistance`, `arrayLevenshteinDistanceWeighted`, `arraySimilarity`** ([#77187](https://github.com/ClickHouse/ClickHouse/pull/77187))
- **`sparseGrams` / `sparseGramsHashes`** and their UTF8 variants ([#78176](https://github.com/ClickHouse/ClickHouse/pull/78176))
- **`hasAll()` uses `tokenbf_v1` and `ngrambf_v1` indices** ([#77662](https://github.com/ClickHouse/ClickHouse/pull/77662))
- **`toInterval(value, unit)`** ([#78723](https://github.com/ClickHouse/ClickHouse/pull/78723))
- **`ALTER DATABASE ... MODIFY COMMENT`** ([#75622](https://github.com/ClickHouse/ClickHouse/pull/75622))
- **`DeltaLakeS3` and `DeltaLakeAzure` table engines** ([#74541](https://github.com/ClickHouse/ClickHouse/pull/74541))
- **Iceberg time travel** — query a table as of a timestamp ([#71072](https://github.com/ClickHouse/ClickHouse/pull/71072), [#77439](https://github.com/ClickHouse/ClickHouse/pull/77439))
- **`IcebergMetadataFilesCache`** ([#77156](https://github.com/ClickHouse/ClickHouse/pull/77156))
- **CPU slot scheduling for workloads** ([#77595](https://github.com/ClickHouse/ClickHouse/pull/77595))
- **In-memory cache for deserialized vector similarity indexes** ([#77905](https://github.com/ClickHouse/ClickHouse/pull/77905))
- **Scram SHA256 authentication** for the PostgreSQL wire protocol ([#76839](https://github.com/ClickHouse/ClickHouse/pull/76839))
- **`serialize_query_plan`** for distributed queries ([#69652](https://github.com/ClickHouse/ClickHouse/pull/69652))
- **`bind_host`** setting for client connections ([#74741](https://github.com/ClickHouse/ClickHouse/pull/74741))
- **Default compression codec** as a MergeTree setting ([#66394](https://github.com/ClickHouse/ClickHouse/pull/66394))

### 🔍 Additional Resources

- **Changelog**: [ClickHouse 25.4](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 25.4.13.22
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- `03` creates two databases (`documented`, `analytics_marts`); the cleanup block at the end of the file drops them

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 25.4 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2025년 4월 30일 출시된 ClickHouse 25.4에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 25.4는 "비교"에 관한 릴리스입니다. Levenshtein 거리가 문자에서 배열 원소 단위로 올라가면서 두 사용자 여정을 단계별로 비교할 수 있게 됐습니다. `sparseGrams`는 고정 `n` 대신 데이터에서 gram 경계를 도출해, 길이가 다른 문자열 간 near-duplicate 탐지가 잘 동작합니다. 그리고 `hasAll()`이 토큰 스킵 인덱스를 사용하게 되어 배열 포함 조건도 프루닝할 수 있습니다.

### 🎯 주요 기능

1. **배열 거리·유사도** — `arrayLevenshteinDistance`, `arrayLevenshteinDistanceWeighted`, `arraySimilarity`
2. **`sparseGrams`** — 데이터 기반 n-gram, 그리고 토큰 인덱스를 쓰는 `hasAll()`
3. **`toInterval`과 수정 가능한 데이터베이스 코멘트**

### 🚀 빠른 시작

```bash
cd local/releases/25.4
./00-setup.sh

./01-array-distance-functions.sh
./02-sparsegrams.sh
./03-tointerval-and-db-comments.sh
```

### 📚 기능 상세

#### 1. 배열 거리·유사도

`arrayLevenshteinDistance(lhs, rhs)`, `arrayLevenshteinDistanceWeighted(lhs, rhs, lhs_weights, rhs_weights)`, `arraySimilarity(...)`은 편집 단위가 문자가 아닌 **배열 원소**인 편집 거리를 계산합니다. ([#77187](https://github.com/ClickHouse/ClickHouse/pull/77187))

**테스트 내용:**
- 치환·삽입·전체 삭제
- 같은 쌍에 대한 `editDistance`와 대비해 원소 단위임을 확인
- 5개 세션 경로를 기준 해피패스와 비교
- 전체 세션 쌍의 거리 분포
- 원소마다 비용을 부여하는 가중 형태
- 체크아웃 이탈이 블로그 방문 이탈보다 비싸도록 가중치 설정
- 가중 거리를 0~1로 정규화하는 `arraySimilarity`
- 유사도 기준 세션 순위
- 가중치 배열과 값 배열의 길이 정합

**핵심 학습 포인트:**
- 원소는 원자적입니다. `['home','checkout']` vs `['home','checkout_v2']`는 편집 **1회**지만, 같은 문자열에 대한 `editDistance`는 3을 보고합니다
- 가중 형태는 배열 4개(양쪽의 값과 가중치)를 받으며, 가중치 배열 길이가 값 배열과 같아야 합니다 — `arrayMap(x -> 1.0, arr)`로 보장할 수 있습니다
- `arraySimilarity`는 동일하면 1, 공통이 없으면 0을 반환해 랭킹 점수로 바로 정렬됩니다
- 비가중 거리는 편집 **횟수**를, 가중 거리는 **비용**을 셉니다. 이 랩에서 치환 1회는 거리 1이지만 가중 거리는 7입니다

#### 2. `sparseGrams`

`sparseGrams`, `sparseGramsHashes`와 `UTF8` 변형은 데이터에서 경계를 도출한 가변 길이 gram을 생성합니다. 별도로 `hasAll()`이 `tokenbf_v1`·`ngrambf_v1` 스킵 인덱스를 참조하게 됐습니다. ([#78176](https://github.com/ClickHouse/ClickHouse/pull/78176), [#77662](https://github.com/ClickHouse/ClickHouse/pull/77662))

**테스트 내용:**
- 짧은 문자열의 gram과 그 길이 분포
- 같은 입력에 대한 고정 `ngrams(s, 3)`와의 비교
- 해시 형태와 결정성 확인
- 한국어 텍스트에서 바이트 vs 문자 동작
- 문서 3개의 공통 gram 수로 near-duplicate 탐지
- gram 중첩 기반 Jaccard 유사도
- `Array(String)` 컬럼의 `tokenbf_v1` 인덱스에 대한 `hasAll()`
- 모든 granule에 있는 태그 vs 좁은 구간에 몰린 태그의 `EXPLAIN indexes = 1`
- 스킵 인덱스 유무에 관계없이 동일한 결과

**핵심 학습 포인트:**
- gram 길이가 다양합니다. 이 랩의 11자 문자열은 3~8자 gram 17개를 만드는 반면 고정 trigram은 9개입니다
- 저장·인덱싱에는 `sparseGramsHashes`가 적합합니다 — 부분 문자열 대신 고정 폭 정수입니다
- 기본 함수는 바이트 기준입니다. 한국어에서 `sparseGrams`는 65개, `sparseGramsUTF8`는 14개를 만들었으니 비ASCII에는 UTF8 변형을 쓰세요
- 한 단어만 다른 두 문장은 공통 gram 67개, Jaccard 0.65였고 무관한 문장은 0.005였습니다
- `hasAll()`이 인덱스를 참조한다고 프루닝되는 건 아닙니다. 모든 granule에 있는 태그는 24/24를 읽고, 군집형 태그는 1/24를 읽습니다
- `use_skip_indexes = 0`과 결과가 같으므로 인덱스는 순수한 최적화입니다

#### 3. `toInterval`과 데이터베이스 코멘트

`toInterval(value, unit)`은 `INTERVAL` 키워드의 함수 형태이고 ([#78723](https://github.com/ClickHouse/ClickHouse/pull/78723)), `ALTER DATABASE ... MODIFY COMMENT`로 생성 이후에도 코멘트를 수정할 수 있습니다 ([#75622](https://github.com/ClickHouse/ClickHouse/pull/75622)).

**테스트 내용:**
- day·hour·minute에 대한 `toInterval`
- month 단위를 포함한 날짜 연산
- `INTERVAL` 키워드와 결과가 정확히 같음을 확인
- 컬럼에서 공급되는 수량
- 데이터셋별 단위를 가진 보존 정책 테이블을 `multiIf`로 해석
- 그 테이블 기준 데이터셋별 만료 행 수
- second~year 전체 단위 어휘
- `CREATE DATABASE ... COMMENT` 이후 `ALTER DATABASE ... MODIFY COMMENT`
- 코멘트로 `system.databases` 검색 및 코멘트 삭제

**핵심 학습 포인트:**
- **값**은 임의의 식이 가능하지만 **단위는 상수 문자열**이어야 합니다 — `toInterval(n, unit_컬럼)`은 `ILLEGAL_TYPE_OF_ARGUMENT`로 실패합니다
- 행마다 단위가 다르면 `multiIf`로 분기하고 각 분기에 자체 상수를 주세요
- 인터벌이 아니라 **결과 시각**으로 분기해야 합니다. 단위가 다른 인터벌은 공통 타입이 없어 `multiIf`가 `NO_COMMON_TYPE`으로 실패합니다
- 데이터베이스 코멘트는 `system.databases`의 조회 가능한 메타데이터라 `WHERE comment ILIKE ...`로 검색 가능한 카탈로그가 됩니다
- 코멘트를 `''`로 설정하면 삭제됩니다

### 🆕 25.4의 새로운 기능

- **`arrayLevenshteinDistance`, `arrayLevenshteinDistanceWeighted`, `arraySimilarity`** ([#77187](https://github.com/ClickHouse/ClickHouse/pull/77187))
- **`sparseGrams` / `sparseGramsHashes`**와 UTF8 변형 ([#78176](https://github.com/ClickHouse/ClickHouse/pull/78176))
- **`hasAll()`이 `tokenbf_v1`·`ngrambf_v1` 인덱스 활용** ([#77662](https://github.com/ClickHouse/ClickHouse/pull/77662))
- **`toInterval(value, unit)`** ([#78723](https://github.com/ClickHouse/ClickHouse/pull/78723))
- **`ALTER DATABASE ... MODIFY COMMENT`** ([#75622](https://github.com/ClickHouse/ClickHouse/pull/75622))
- **`DeltaLakeS3`·`DeltaLakeAzure` 테이블 엔진** ([#74541](https://github.com/ClickHouse/ClickHouse/pull/74541))
- **Iceberg 타임 트래블** — 특정 시점 기준 조회 ([#71072](https://github.com/ClickHouse/ClickHouse/pull/71072), [#77439](https://github.com/ClickHouse/ClickHouse/pull/77439))
- **`IcebergMetadataFilesCache`** ([#77156](https://github.com/ClickHouse/ClickHouse/pull/77156))
- **워크로드 CPU 슬롯 스케줄링** ([#77595](https://github.com/ClickHouse/ClickHouse/pull/77595))
- **역직렬화된 벡터 유사도 인덱스의 인메모리 캐시** ([#77905](https://github.com/ClickHouse/ClickHouse/pull/77905))
- **PostgreSQL 와이어 프로토콜의 Scram SHA256 인증** ([#76839](https://github.com/ClickHouse/ClickHouse/pull/76839))
- **분산 쿼리용 `serialize_query_plan`** ([#69652](https://github.com/ClickHouse/ClickHouse/pull/69652))
- **클라이언트 연결의 `bind_host` 설정** ([#74741](https://github.com/ClickHouse/ClickHouse/pull/74741))
- **MergeTree 설정으로서의 기본 압축 코덱** ([#66394](https://github.com/ClickHouse/ClickHouse/pull/66394))

### 🔍 추가 자료

- **Changelog**: [ClickHouse 25.4](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse 공식 문서**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 참고사항

- 모든 기능은 ClickHouse 25.4.13.22에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- `03`은 데이터베이스 2개(`documented`, `analytics_marts`)를 만듭니다 — 파일 끝의 정리 블록에서 삭제합니다

---

**Happy Learning! 🚀**
