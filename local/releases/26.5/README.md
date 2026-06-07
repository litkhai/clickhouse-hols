# ClickHouse 26.5 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.5 new features. This directory focuses on verified and working features newly added in ClickHouse 26.5 (released 2026-05-21).

### 📋 Overview

ClickHouse 26.5 sharpens the SQL surface for introspection and ergonomics: the new `filesystem()` table function lets you query directory trees as tables, higher-order functions accept bare function names (cutting lambda boilerplate), and `tokenizeQuery` / `highlightQuery` expose the lexer and parser to SQL itself. Number-theory primitives (`isPrime`, `isProbablePrime`) round out a release packed with developer-experience improvements.

### 🎯 Key Features Covered

1. **`filesystem()` Table Function** — query directories, file metadata, and contents as a SQL table
2. **Bare Function Names + `isPrime` / `isProbablePrime`** — `arrayMap(negate, [1,2,3])` and primality testing
3. **`tokenizeQuery` + `highlightQuery`** — lexer/parser introspection for SQL strings

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/26.5
./00-setup.sh

./01-filesystem-function.sh
./02-higher-order-primes.sh
./03-tokenize-highlight-query.sh
```

### 📚 Feature Details

#### 1. `filesystem()` Table Function (01-filesystem-function)

**New Feature:** A new `filesystem('path')` table function exposes the contents of a directory (relative to `user_files`) as a SQL table with one row per entry. Columns include `name`, `type`, `size`, `depth`, `modification_time`, `content`, and full Unix permission flags. ([#53610](https://github.com/ClickHouse/ClickHouse/pull/53610))

**Test Content:**
- Creating sample files via `INSERT INTO FUNCTION file(...)`
- Schema inspection (`DESCRIBE filesystem('.')`)
- Listing all entries with metadata
- Files-only filter + size formatting
- Reading file contents inline
- Extension and permission filtering
- Aggregations over the filesystem
- Recently-modified files (last hour)
- Pairing `filesystem()` discovery with `file()` data reads
- Unix permission audit string rendering

**Key Learning Points:**
- `filesystem()` reads relative to `/var/lib/clickhouse/user_files` (`user_files_path` config)
- The `content` column gives you the entire file body as a `Nullable(String)` — be careful with large files
- Directory entries have `size = NULL`; real files have a `size` and `content`
- 22 columns are available (name, type, size, depth, mtime, permissions, etc.)
- Combine with `file()` table function to discover then process files in one query

**Use Cases:**
- Operational queries against staged ingest files
- Auditing user_files directory (sizes, ages, permissions)
- Cataloging data lake snapshots stored on local disk
- Building self-service file browsers backed by SQL
- Identifying stale or oversized staged files for cleanup

---

#### 2. Bare Function Names + `isPrime` / `isProbablePrime` (02-higher-order-primes)

**New Features:**
- Higher-order functions (`arrayMap`, `arrayFilter`, `arrayCount`, `arraySum`, etc.) now accept a **bare function name** instead of requiring a lambda. `arrayMap(negate, [1,2,3])` is equivalent to `arrayMap(x -> negate(x), [1,2,3])`. ([#101033](https://github.com/ClickHouse/ClickHouse/pull/101033))
- `isPrime(n)` — exact primality test for `UInt64` ([#104234](https://github.com/ClickHouse/ClickHouse/pull/104234))
- `isProbablePrime(n [, rounds])` — Miller-Rabin probabilistic test for up to `UInt256`, with configurable confidence (default 25 rounds, FP rate < 10⁻¹⁵)

**Test Content:**
- Old vs new syntax (`x -> negate(x)` vs `negate`)
- `arrayFilter(isPrime, [...])` — predicate as bare function
- `isPrime` on small numbers
- `isProbablePrime` on `UInt128` and `UInt256` values (including Mersenne primes)
- Configurable `rounds` parameter for confidence tuning
- `arrayCount(isPrime, range(2,100))` and `arraySum(arrayFilter(isPrime, ...))`
- Mixed lambda + bare function usage

**Key Learning Points:**
- Any single-argument function with the right signature can be used bare
- Bare-function form is shorter and avoids accidental variable shadowing in nested lambdas
- `isPrime` is exact only for `UInt64`; for wider types use `isProbablePrime`
- `isProbablePrime` returns `0` for "definitely composite" and `1` for "probably prime"
- More `rounds` = higher confidence at the cost of CPU; the default is sufficient for almost all use cases

**Use Cases:**
- Cleaner functional-style SQL
- Number-theory experiments, cryptographic preliminaries
- Validating user-provided primes (e.g. RSA parameter checks)
- Generating prime-numbered IDs, hash-table sizes

---

#### 3. `tokenizeQuery` + `highlightQuery` (03-tokenize-highlight-query)

**New Features:**
- `tokenizeQuery(s)` returns `Array(Tuple(start, end, token_type))` — the **lexer**'s token stream for a SQL string (BareWord, Number, Whitespace, StringLiteral, …)
- `highlightQuery(s)` returns `Array(Tuple(start, end, category))` — the **parser**'s syntax-highlight ranges with semantic categories (keyword, identifier, function, number, string, …)
- ([#101054](https://github.com/ClickHouse/ClickHouse/pull/101054))

**Test Content:**
- `tokenizeQuery` on simple and complex queries
- Token-by-token decomposition via `ARRAY JOIN`
- Token-type frequency analysis
- `highlightQuery` basics (SELECT, CREATE TABLE)
- Building a per-token highlight breakdown
- Side-by-side comparison: lexer-level (many tokens) vs parser-level (semantic spans)
- Identifier extraction from a query corpus (real use case)
- Keyword frequency across a query log

**Key Learning Points:**
- `tokenizeQuery` is finer-grained: every whitespace, operator, and bare word is its own token
- `highlightQuery` collapses tokens into semantic units (a function call is one span)
- Tuple offsets are **byte positions** — slice the original string with `substring(q, t.1 + 1, t.2 - t.1)`
- These functions enable SQL-driven query-log analysis without any external parser
- Categories from `highlightQuery` include: `keyword`, `identifier`, `function`, `number`, `string`

**Use Cases:**
- Custom query-log analytics (identifier inventories, keyword usage)
- Detecting unusual queries by token-shape signature
- Building schema-aware autocomplete or linting in custom tooling
- Pre-processing for SQL-similarity / clustering pipelines

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
docker logs clickhouse-26-5
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.5/
├── README.md                          # This document
├── 00-setup.sh                        # ClickHouse 26.5 installation script
├── 01-filesystem-function.sh          # filesystem() runner
├── 01-filesystem-function.sql         # filesystem() SQL
├── 02-higher-order-primes.sh          # Bare names + primes runner
├── 02-higher-order-primes.sql         # Bare names + primes SQL
├── 03-tokenize-highlight-query.sh     # tokenizeQuery / highlightQuery runner
└── 03-tokenize-highlight-query.sql    # tokenizeQuery / highlightQuery SQL
```

### 🆕 What's New in 26.5

- **`filesystem()`** table function
- **Bare function names** in higher-order functions
- **`tokenizeQuery` / `highlightQuery`** for SQL introspection
- **`isPrime` / `isProbablePrime`** number-theory primitives
- **`regexpPosition`** (with PostgreSQL-compatible `regexpInstr` / `regexp_instr` aliases)
- **`prettyPrintJSON`** function
- **`STRING_AGG`** case-insensitive alias for `groupConcat`
- **Negative `LIMIT BY`** — `LIMIT -2 BY id` selects last N rows per group
- **Multi-path `Tuple` / `Array` JSONPath** in `JSON_VALUE`, `JSON_EXISTS`, `JSON_QUERY`
- **`url_base` setting** for relative URL resolution in `url()` / `URL` engine
- **`CREATE OR REPLACE MATERIALIZED VIEW`** with atomic-swap semantics
- **`SYSTEM PAUSE VIEW`** for refreshable materialized views
- **`system.zookeeper_watches`** system table
- **`AvroConfluent` output format** (was input-only)
- **`Paimon` table engine** with incremental snapshot tracking
- **Independent subquery `use_query_cache`** with `query_cache_for_subqueries` setting
- **Web UI syntax highlighting** in `play.html`
- **Experimental Web Terminal** at `/webterminal` (browser-based clickhouse-client over WebSocket)
- **Experimental WASM UDFs** can now be declared `DETERMINISTIC`
- **Spill-to-grace-hash auto-enabled** at `max_bytes_ratio_before_external_join = 0.5`

### 🔍 Additional Resources

- **Release Presentation**: [ClickHouse 26.5](https://presentations.clickhouse.com/2026-release-26.5/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=P1IDAvsi7p8)
- **Web Terminal Demo**: [play.clickhouse.com/webterminal?user=play](https://play.clickhouse.com/webterminal?user=play)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 26.5.1
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- The `filesystem()` test creates files in `user_files` — remove with `docker exec clickhouse-26-5 rm /var/lib/clickhouse/user_files/demo_*` if desired

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse 26.5 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 5월 21일 출시된 ClickHouse 26.5에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 26.5는 인트로스펙션과 사용성을 위한 SQL 표면을 다듬습니다: 새로운 `filesystem()` 테이블 함수로 디렉토리 트리를 테이블처럼 조회하고, 고차 함수가 베어 함수 이름을 받아들여 람다 보일러플레이트를 줄이며, `tokenizeQuery` / `highlightQuery`가 렉서와 파서를 SQL에 노출합니다. 수론 함수 (`isPrime`, `isProbablePrime`)가 개발자 경험 개선에 추가됩니다.

### 🎯 주요 다루는 기능

1. **`filesystem()` 테이블 함수** — 디렉토리, 파일 메타데이터, 내용을 SQL 테이블로 조회
2. **베어 함수 이름 + `isPrime` / `isProbablePrime`** — `arrayMap(negate, [1,2,3])` 와 소수 판정
3. **`tokenizeQuery` + `highlightQuery`** — SQL 문자열의 렉서/파서 인트로스펙션

### 🚀 빠른 시작

```bash
cd local/releases/26.5
./00-setup.sh

./01-filesystem-function.sh
./02-higher-order-primes.sh
./03-tokenize-highlight-query.sh
```

### 📚 기능 상세

#### 1. `filesystem()` 테이블 함수

`filesystem('path')`는 디렉토리(기본 `user_files` 기준)의 내용을 항목당 한 행씩 SQL 테이블로 노출합니다. 컬럼은 `name`, `type`, `size`, `depth`, `modification_time`, `content`, 전체 Unix 권한 플래그를 포함합니다. ([#53610](https://github.com/ClickHouse/ClickHouse/pull/53610))

**테스트 내용:**
- `INSERT INTO FUNCTION file(...)`로 샘플 파일 생성
- 스키마 검사 (`DESCRIBE filesystem('.')`)
- 모든 항목 메타데이터 조회
- 파일만 필터링 + 크기 포맷
- 파일 내용 인라인 읽기
- 확장자 및 권한 필터링
- 파일시스템 통계 집계
- 최근 수정 파일 (지난 1시간)
- `filesystem()` 발견 + `file()` 데이터 읽기 결합
- Unix 권한 감사 문자열 렌더링

#### 2. 베어 함수 이름 + `isPrime` / `isProbablePrime`

- 고차 함수 (`arrayMap`, `arrayFilter`, `arrayCount`, `arraySum` 등)가 람다 대신 **베어 함수 이름**을 받습니다. ([#101033](https://github.com/ClickHouse/ClickHouse/pull/101033))
- `isPrime(n)` — `UInt64`의 정확한 소수 판정
- `isProbablePrime(n [, rounds])` — `UInt256`까지의 Miller-Rabin 확률적 판정 ([#104234](https://github.com/ClickHouse/ClickHouse/pull/104234))

**테스트 내용:**
- 기존 vs 새 구문 (`x -> negate(x)` vs `negate`)
- `arrayFilter(isPrime, [...])` — 베어 함수 술어
- 소수 판정
- `UInt128`/`UInt256` Mersenne 소수 등 큰 수 확률 판정
- 신뢰도 조정용 `rounds` 파라미터
- `arrayCount`, `arraySum`과 결합

#### 3. `tokenizeQuery` + `highlightQuery`

- `tokenizeQuery(s)` — SQL 문자열의 **렉서** 토큰 스트림 반환 (BareWord, Number, Whitespace 등)
- `highlightQuery(s)` — **파서** 기반 구문 강조 범위 (keyword, identifier, function 등)
- ([#101054](https://github.com/ClickHouse/ClickHouse/pull/101054))

**테스트 내용:**
- 단순/복합 쿼리 `tokenizeQuery`
- `ARRAY JOIN`으로 토큰 단위 분해
- 토큰 타입 빈도 분석
- `highlightQuery` 기초 (SELECT, CREATE TABLE)
- 토큰별 강조 카테고리 분해
- 비교: 렉서 (많은 토큰) vs 파서 (의미 단위 범위)
- 쿼리 코퍼스에서 식별자 추출
- 쿼리 로그에서 키워드 빈도

### 🆕 26.5의 새로운 기능

- **`filesystem()`** 테이블 함수
- 고차 함수의 **베어 함수 이름**
- **`tokenizeQuery` / `highlightQuery`** SQL 인트로스펙션
- **`isPrime` / `isProbablePrime`** 수론 함수
- **`regexpPosition`** (`regexpInstr` / `regexp_instr` PostgreSQL 호환 별칭)
- **`prettyPrintJSON`**
- **`STRING_AGG`** — `groupConcat`의 대소문자 무시 별칭
- **음수 `LIMIT BY`** — `LIMIT -2 BY id`로 각 그룹의 마지막 N개 행
- 다중 경로 `Tuple` / `Array` JSONPath
- `url_base` 설정
- **`CREATE OR REPLACE MATERIALIZED VIEW`** 원자적 스왑
- **`SYSTEM PAUSE VIEW`**
- **`system.zookeeper_watches`** 시스템 테이블
- **`AvroConfluent` 출력 포맷**
- **`Paimon` 테이블 엔진** 증분 스냅샷 추적
- **독립 서브쿼리 `use_query_cache`** + `query_cache_for_subqueries` 설정
- Web UI 구문 강조 (`play.html`)
- **실험적 Web Terminal** — `/webterminal`
- **WASM UDF** `DETERMINISTIC` 선언
- **Grace hash join 자동 스필** 기본 활성화 (`max_bytes_ratio_before_external_join = 0.5`)

### 🔍 추가 자료

- **Release Presentation**: [ClickHouse 26.5](https://presentations.clickhouse.com/2026-release-26.5/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=P1IDAvsi7p8)
- **Web Terminal Demo**: [play.clickhouse.com/webterminal](https://play.clickhouse.com/webterminal?user=play)

### 📝 참고사항

- 모든 기능은 ClickHouse 26.5.1에서 검증
- 각 스크립트는 독립적으로 실행 가능
- `filesystem()` 테스트는 `user_files`에 파일을 생성합니다 — 정리: `docker exec clickhouse-26-5 rm /var/lib/clickhouse/user_files/demo_*`

---

**Happy Learning! 🚀**
