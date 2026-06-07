# ClickHouse 26.2 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.2 new features. This directory focuses on verified and working features newly added in ClickHouse 26.2 (released 2026-02-26).

### 📋 Overview

ClickHouse 26.2 expands the SQL surface area with number-theory utilities, a new 128-bit hash function, and an introspectable text-index tokenizer catalog. The release also makes the text index GA, promotes the QBit vector type to GA, and adds distributed vector search.

### 🎯 Key Features Covered

1. **`primes()` Table Function + `system.primes`** — prime numbers as a first-class SQL source
2. **`xxh3_128` Hash Function** — 128-bit non-cryptographic hash for deduplication, sharding, and joins
3. **`system.tokenizers` Catalog** — discover every tokenizer available to text indexes from SQL

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
# 1. Install and start ClickHouse 26.2
cd local/releases/26.2
./00-setup.sh

# 2. Run feature tests
./01-primes-function.sh
./02-xxh3-128-hash.sh
./03-system-tokenizers.sh
```

#### Manual Execution (SQL only)

```bash
cd ../../oss-mac-setup
./client.sh 8123

cd ../local/releases/26.2
source 01-primes-function.sql
```

### 📚 Feature Details

#### 1. `primes()` Table Function & `system.primes` (01-primes-function)

**New Feature:** A new table function `primes(n)` returns the first `n` prime numbers, and `system.primes` exposes an unbounded stream of primes — a single column named `prime` of type `UInt64`. ([#92776](https://github.com/ClickHouse/ClickHouse/pull/92776))

**Test Content:**
- Reading from `system.primes` with `LIMIT` and `WHERE`
- Generating bounded prime sequences via `primes(n)`
- Twin-prime pair detection with self-JOIN on row number
- Prime-gap distribution analysis
- Composite-number identification via `NOT IN (primes)`
- Building a materialized prime cache table
- Nearest-prime lookup for hash-table sizing

**Key Learning Points:**
- Both `primes()` and `system.primes` use a single column named `prime` (not `number`)
- `system.primes` is unbounded — always pair with `LIMIT` or a `WHERE prime < X` predicate
- `primes(n)` is bounded and is the safer choice when you know the upper bound
- Combine with `rowNumberInAllBlocks()` to access ordinal position

**Use Cases:**
- Hash-table bucket sizing (use the next prime ≥ desired capacity)
- Modular arithmetic and number-theory experiments
- Generating test/synthetic data with deterministic distinctness
- Teaching and demonstrations

---

#### 2. `xxh3_128` Hash Function (02-xxh3-128-hash)

**New Feature:** 128-bit XXH3 hash returning `UInt128`, doubling the hash space of the existing `xxHash64` at comparable throughput. ([#96055](https://github.com/ClickHouse/ClickHouse/pull/96055))

**Test Content:**
- Basic hashing and `UInt128` result type inspection
- Hex / decimal representations side-by-side with `xxHash64`
- Content-fingerprint deduplication via `MATERIALIZED` column
- Hash-based shard mapping
- Collision test on 10,000 random strings
- JOIN on 128-bit fingerprints

**Key Learning Points:**
- Result type is `UInt128` (32 hex chars vs `xxHash64`'s 16)
- Same input → same hash (deterministic, no salt)
- Use as a `MATERIALIZED` column for cheap, indexable content fingerprints
- Practical collision probability is negligible at typical data sizes
- The function name is `xxh3_128`, while the existing 64-bit equivalent is `xxHash64` (note the camel-case asymmetry)

**Use Cases:**
- Deduplication where 64-bit collision risk is unacceptable
- Sharding keys for very large key spaces
- Content-addressable joins across tables
- Idempotency keys / cache lookups

---

#### 3. `system.tokenizers` Catalog (03-system-tokenizers)

**New Feature:** `system.tokenizers` system table lists every tokenizer registered for use with `text` indexes and the `tokens()` function. ([#96753](https://github.com/ClickHouse/ClickHouse/pull/96753))

**Test Content:**
- Listing all tokenizers from `system.tokenizers`
- Calling `tokens(s, tokenizer_name [, params])` with different tokenizers (splitByNonAlpha, splitByString, ngrams)
- Creating a `text` index with an explicit tokenizer
- Full-text search via `hasToken` driven by the index
- Token count per document
- `EXPLAIN indexes = 1` to confirm the skip index is used
- Side-by-side comparison of tokenizer output

**Key Learning Points:**
- Available tokenizers include `splitByNonAlpha`, `splitByString`, `ngrams`, `ngrambf_v1`, `tokenbf_v1`, `sparseGrams`, `sparse_grams`, `array`
- `text` indexes are now GA in 26.2 (no compatibility flag required)
- `tokens(string, tokenizer_name)` lets you preview what the index will store before building it
- Tokenizer choice directly determines what queries the index can accelerate

**Use Cases:**
- Choosing the right tokenizer before building a large text index
- Validating tokenization behavior against multilingual or structured text
- Diagnosing why a text-index query is or isn't being skipped

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
docker logs clickhouse-26-2
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.2/
├── README.md                     # This document
├── 00-setup.sh                   # ClickHouse 26.2 installation script
├── 01-primes-function.sh         # primes()/system.primes test runner
├── 01-primes-function.sql        # primes()/system.primes SQL
├── 02-xxh3-128-hash.sh           # xxh3_128 test runner
├── 02-xxh3-128-hash.sql          # xxh3_128 SQL
├── 03-system-tokenizers.sh       # system.tokenizers test runner
└── 03-system-tokenizers.sql      # system.tokenizers SQL
```

### 🆕 What's New in 26.2

- **Text index is now GA** — no more `allow_experimental_*` flag, survives backup restores
- **QBit data type GA** — quantized bit-packed vectors for approximate nearest-neighbor search
- **Distributed vector search** — vector indexes can now be sharded across replicas
- **TOTP authentication** — time-based one-time passwords as a server-side auth method
- **`primes()` and `system.primes`** — prime numbers as a SQL source
- **`xxh3_128`** — 128-bit non-cryptographic hash
- **`system.tokenizers`**, **`system.user_defined_functions`**, **`system.jemalloc_stats`**, **`system.jemalloc_profile_text`**, **`system.fail_points`** — five new introspection tables
- **`OPTIMIZE … DRY RUN PARTS`** — simulate merges without committing
- **`lazy_load_tables` database setting** — defer table-engine instantiation to first access
- **ClickStack observability UI** — bundled directly with the server
- **Google BigLake catalog integration** — query BigLake-managed Iceberg tables

### 🔍 Additional Resources

- **Release Presentation**: [ClickHouse 26.2 Community Call](https://presentations.clickhouse.com/2026-release-26.2/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=7qHba08vNfo)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2026](https://clickhouse.com/docs/whats-new/changelog)

### 📝 Notes

- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out by default for inspection
- All features have been verified on ClickHouse 26.2.19

---

**Happy Learning! 🚀**

For questions or issues, see the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse 26.2 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 2월 26일 출시된 ClickHouse 26.2에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 26.2는 수론 유틸리티, 새로운 128비트 해시 함수, 그리고 검색 가능한 텍스트 인덱스 토크나이저 카탈로그로 SQL 표면을 확장합니다. 또한 텍스트 인덱스가 GA로 승격되고, QBit 벡터 타입이 GA가 되었으며, 분산 벡터 검색이 추가되었습니다.

### 🎯 주요 다루는 기능

1. **`primes()` 테이블 함수 + `system.primes`** — 소수를 SQL 소스로 직접 활용
2. **`xxh3_128` 해시 함수** — 중복 제거·샤딩·조인을 위한 128비트 비암호 해시
3. **`system.tokenizers` 카탈로그** — 텍스트 인덱스용 토크나이저 목록을 SQL로 조회

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (Docker Desktop 설치)
- [oss-mac-setup](../../oss-mac-setup/) 환경

#### 설정 및 실행

```bash
# 1. ClickHouse 26.2 설치 및 시작
cd local/releases/26.2
./00-setup.sh

# 2. 각 기능별 테스트 실행
./01-primes-function.sh
./02-xxh3-128-hash.sh
./03-system-tokenizers.sh
```

### 📚 기능 상세

#### 1. `primes()` 테이블 함수 & `system.primes`

새 테이블 함수 `primes(n)`은 첫 `n`개의 소수를 반환하고, `system.primes`는 무한 소수 스트림을 제공합니다. 컬럼명은 `prime`(UInt64) 하나입니다. ([#92776](https://github.com/ClickHouse/ClickHouse/pull/92776))

**테스트 내용:**
- `LIMIT`/`WHERE`로 `system.primes` 조회
- `primes(n)`로 유한 소수 시퀀스 생성
- 행 번호 자기 조인으로 쌍둥이 소수 탐색
- 소수 간격(prime gap) 분포 분석
- `NOT IN (primes)`로 합성수 식별
- 소수 캐시 테이블 구축
- 해시 테이블 크기용 최근접 소수 검색

#### 2. `xxh3_128` 해시 함수

`UInt128`을 반환하는 128비트 XXH3 해시 — 기존 `xxHash64`의 해시 공간을 두 배로 확장하면서 비슷한 처리량을 유지합니다. ([#96055](https://github.com/ClickHouse/ClickHouse/pull/96055))

**테스트 내용:**
- 기본 해싱 및 `UInt128` 결과 타입 확인
- `xxHash64`와의 16진수/십진수 표현 비교
- `MATERIALIZED` 컬럼을 통한 콘텐츠 지문 기반 중복 제거
- 해시 기반 샤드 매핑
- 10,000개 랜덤 문자열 충돌 테스트
- 128비트 지문 기반 JOIN

#### 3. `system.tokenizers` 카탈로그

`system.tokenizers`는 `text` 인덱스와 `tokens()` 함수에서 사용 가능한 모든 토크나이저를 보여줍니다. ([#96753](https://github.com/ClickHouse/ClickHouse/pull/96753))

**테스트 내용:**
- `system.tokenizers`에서 토크나이저 목록 조회
- 다양한 토크나이저로 `tokens(s, name [, params])` 호출
- 명시적 토크나이저로 `text` 인덱스 생성
- 인덱스를 활용한 `hasToken` 전체 텍스트 검색
- 문서별 토큰 개수 계산
- `EXPLAIN indexes = 1`로 스킵 인덱스 사용 확인

### 🆕 26.2의 새로운 기능

- **Text 인덱스 GA** — 실험 플래그 불필요, 백업 복원 시에도 유지
- **QBit 데이터 타입 GA** — 근사 최근접 이웃 검색용 양자화 비트팩 벡터
- **분산 벡터 검색** — 벡터 인덱스를 복제본에 걸쳐 샤딩
- **TOTP 인증** — 시간 기반 일회용 비밀번호 서버 인증
- **`primes()` / `system.primes`** — 소수를 SQL 소스로
- **`xxh3_128`** — 128비트 비암호 해시
- **`system.tokenizers`, `system.user_defined_functions`, `system.jemalloc_stats`** 등 — 5개의 새로운 인트로스펙션 테이블
- **`OPTIMIZE … DRY RUN PARTS`** — 커밋 없이 머지 시뮬레이션
- **`lazy_load_tables`** — 테이블 엔진 인스턴스화 지연
- **ClickStack 옵저버빌리티 UI** — 서버에 번들 포함
- **Google BigLake 카탈로그 통합**

### 🔍 추가 자료

- **Release Presentation**: [ClickHouse 26.2 Community Call](https://presentations.clickhouse.com/2026-release-26.2/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=7qHba08vNfo)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 내에서 생성됨
- 정리(cleanup) 구문은 기본적으로 주석 처리됨
- 모든 기능은 ClickHouse 26.2.19에서 검증됨

---

**Happy Learning! 🚀**

질문이나 이슈는 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
