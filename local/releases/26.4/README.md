# ClickHouse 26.4 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.4 new features. This directory focuses on verified and working features newly added in ClickHouse 26.4 (released 2026-04-30).

### 📋 Overview

ClickHouse 26.4 is a SQL-ergonomics release: `NATURAL JOIN` and `VALUES` clauses cut JOIN boilerplate, two new array primitives (`arrayTranspose` and `arrayAutocorrelation`) bring matrix and time-series utilities to SQL, and a trio of text helpers (`obfuscateQuery`, `highlight`, non-constant `printf`) round out the string toolkit. The release also makes automatic JOIN spilling to grace hash join the default behavior.

### 🎯 Key Features Covered

1. **`NATURAL JOIN` + `VALUES` Table Expression** — SQL-standard join syntax and inline tables
2. **`arrayTranspose` + `arrayAutocorrelation`** — matrix transpose and time-series autocorrelation
3. **`obfuscateQuery` + `highlight` + per-row `printf`** — text transformation toolkit

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/26.4
./00-setup.sh

./01-natural-join-values.sh
./02-array-functions.sh
./03-string-text-functions.sh
```

### 📚 Feature Details

#### 1. `NATURAL JOIN` + `VALUES` Table Expression (01-natural-join-values)

**New Features:**
- `NATURAL JOIN` — automatically matches on all same-named columns and deduplicates them in the result. ([#99840](https://github.com/ClickHouse/ClickHouse/pull/99840))
- `VALUES (...) AS t(col, ...)` — SQL-standard `VALUES` clause usable as a table expression in `FROM`. ([#100143](https://github.com/ClickHouse/ClickHouse/pull/100143))

**Test Content:**
- `VALUES` as the source of a `SELECT`, inside CTEs, and as the right side of a join
- `NATURAL JOIN` between two tables sharing one column
- Column-count comparison vs explicit `JOIN ... ON`
- `NATURAL JOIN` driven entirely by `VALUES` literals
- Country-code lookup pattern (replace temp tables with inline `VALUES`)
- Multi-column `NATURAL JOIN` (region + category)

**Key Learning Points:**
- `NATURAL JOIN` makes joins concise but is implicit — readers must inspect the schema to know what is being joined
- Use it for ad-hoc analytics; prefer explicit `JOIN ... USING (col)` in production for clarity
- `VALUES` works as a real table expression — supports `ORDER BY`, `LIMIT`, joins
- Combine `VALUES` with CTEs to inline small reference tables without DDL

**Use Cases:**
- Quick lookups against a small static mapping (country → name, currency → rate)
- Demos and tutorials (no `CREATE TABLE` needed)
- Migration from PostgreSQL / SQL Server scripts that already use `VALUES`
- Reducing JOIN boilerplate in star-schema queries

---

#### 2. `arrayTranspose` + `arrayAutocorrelation` (02-array-functions)

**New Features:**
- `arrayTranspose(matrix)` — transpose a 2-D array (rows ↔ columns). ([#101214](https://github.com/ClickHouse/ClickHouse/pull/101214))
- `arrayAutocorrelation(arr [, max_lag])` — normalized autocorrelation at each lag from 0 up to `max_lag`. ([#94776](https://github.com/ClickHouse/ClickHouse/pull/94776))

**Test Content:**
- 2×3 → 3×2 transpose, square transpose, single-row → column-vector
- Round-trip identity `arrayTranspose(arrayTranspose(M)) = M`
- Pivot use case: rows-of-records → columns-of-fields
- Autocorrelation of a linear ramp, constant array, and random noise
- Detecting weekly seasonality (period 7) in a synthetic 28-day series
- Custom `max_lag` parameter
- Combined: per-row autocorrelation after transposing a stack of signals

**Key Learning Points:**
- `arrayTranspose` expects a "rectangular" array of arrays — all inner arrays must be the same length
- Element type is preserved (numbers stay numbers, strings stay strings)
- `arrayAutocorrelation` returns lag 0 as `1.0` (perfect self-correlation)
- Constant arrays produce `NaN` autocorrelation (zero variance, undefined denominator)
- A strong peak at lag `k` indicates periodicity with period `k`

**Use Cases:**
- Matrix-style data manipulation in SQL (no `ARRAY JOIN` ceremony)
- Quick pivot from row-store to column-store views
- Detecting seasonality in time-series stored as arrays
- Time-series quality checks (random noise should yield near-zero autocorrelation)
- Mathematical and statistical pipelines

---

#### 3. `obfuscateQuery` + `highlight` + Non-Constant `printf` (03-string-text-functions)

**New Features:**
- `obfuscateQuery(s)` — replace identifiers and literals with deterministic random substitutes, preserving SQL structure. ([#98305](https://github.com/ClickHouse/ClickHouse/pull/98305))
- `highlight(text, terms [, open_tag, close_tag])` — wrap each occurrence of any term in HTML tags (default `<em>`/`</em>`). ([#99131](https://github.com/ClickHouse/ClickHouse/pull/99131))
- `printf` now accepts a **non-constant** format string, allowing per-row formats. ([#98991](https://github.com/ClickHouse/ClickHouse/pull/98991))

**Test Content:**
- Basic `obfuscateQuery` on simple and complex SQL
- Determinism check (same input → same output)
- Batch obfuscation of three different queries
- `highlight` with default and custom tags, case-insensitive matching
- Search-results pipeline using `highlight` on real article text
- Per-row format strings (decimal, hex, octal, zero-padded)
- Mixed-format logging output
- Combined pipeline: filter → highlight → format

**Key Learning Points:**
- `obfuscateQuery` is deterministic — same query always obfuscates to the same output (good for de-duplicating query patterns in logs)
- `highlight` does ASCII case-insensitive matching; for international text combine with `caseFoldUTF8` (added in 26.3)
- Non-constant `printf` enables data-driven formatting — useful for log rendering and report generation
- `highlight` automatically merges overlapping matches

**Use Cases:**
- Safely sharing slow-query reports without exposing PII or sensitive identifiers
- Building search-results UIs (highlight matched terms in snippets)
- Generating reports / logs with mixed numeric formats per row
- Query-pattern deduplication for capacity planning

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
docker logs clickhouse-26-4
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.4/
├── README.md                     # This document
├── 00-setup.sh                   # ClickHouse 26.4 installation script
├── 01-natural-join-values.sh     # NATURAL JOIN + VALUES test runner
├── 01-natural-join-values.sql    # NATURAL JOIN + VALUES SQL
├── 02-array-functions.sh         # arrayTranspose + arrayAutocorrelation runner
├── 02-array-functions.sql        # Array functions SQL
├── 03-string-text-functions.sh   # obfuscateQuery + highlight + printf runner
└── 03-string-text-functions.sql  # String/text functions SQL
```

### 🆕 What's New in 26.4

- **Automatic JOIN spilling** to grace hash join when memory limit is reached (default behavior)
- **Arrow Flight SQL** support
- **`NATURAL JOIN`** syntax
- **`VALUES`** as a table expression in `FROM`
- **`arrayTranspose`** and **`arrayAutocorrelation`**
- **`obfuscateQuery`**, **`highlight`**, **non-constant `printf`**
- **PostgreSQL-compatible `EXTRACT` units** — `EPOCH`, `DOW`, `DOY`, `ISODOW`, `ISOYEAR`, `WEEK`, `CENTURY`, `DECADE`, `MILLENNIUM`
- **SQL-standard compound intervals** — `INTERVAL '1:30' HOUR TO MINUTE`
- **`hasPhrase` / `matchPhrase`** — phrase search (continuous sequences of tokens)
- **`commit_order` projection index** — keep data in insertion order
- **MergeTree skip-index for JSON columns** — `bloom_filter`, `tokenbf_v1`, `ngrambf_v1`, `text` on `JSONAllPaths`
- **Bucketed serialization for Map columns** — 2-49× faster single-key lookups
- **`stem` function GA** — was previously experimental
- **Map/JSON values in dictionary attributes**
- **`auto_statistics_types` defaults to `'minmax, uniq'`** — automatic stats on new tables
- **`Date + Time`** addition produces `DateTime`/`DateTime64`
- **Quotas by normalized-query-hash** — limit per query-pattern
- **`SET TIME ZONE`** as an alias for `SET session_timezone`
- **Text index GA** stays enabled regardless of `compatibility` setting
- **Experimental: `aiGenerate`** function for OpenAI / Anthropic LLM calls from SQL

### 🔍 Additional Resources

- **Release Presentation**: [ClickHouse 26.4](https://presentations.clickhouse.com/2026-release-26.4/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=9lSVy7k2EoI)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 26.4.3
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection

---

**Happy Learning! 🚀**

---

## 한국어

ClickHouse 26.4 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 4월 30일 출시된 ClickHouse 26.4에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 26.4는 SQL 사용성 강화 릴리스입니다: `NATURAL JOIN`과 `VALUES` 절로 JOIN 보일러플레이트를 줄이고, 두 가지 새로운 배열 함수(`arrayTranspose`, `arrayAutocorrelation`)로 행렬·시계열 유틸리티를 SQL에 도입하며, 세 가지 텍스트 헬퍼(`obfuscateQuery`, `highlight`, 비상수 `printf`)로 문자열 도구를 보강합니다. 또한 메모리 한도 도달 시 grace hash join으로의 자동 스필이 기본 동작이 되었습니다.

### 🎯 주요 다루는 기능

1. **`NATURAL JOIN` + `VALUES` 테이블 표현식** — SQL 표준 조인 구문과 인라인 테이블
2. **`arrayTranspose` + `arrayAutocorrelation`** — 행렬 전치 및 시계열 자기상관
3. **`obfuscateQuery` + `highlight` + 행별 `printf`** — 텍스트 변환 툴킷

### 🚀 빠른 시작

```bash
cd local/releases/26.4
./00-setup.sh

./01-natural-join-values.sh
./02-array-functions.sh
./03-string-text-functions.sh
```

### 📚 기능 상세

#### 1. `NATURAL JOIN` + `VALUES`

- `NATURAL JOIN` — 동일 이름 컬럼으로 자동 매칭, 중복 제거 ([#99840](https://github.com/ClickHouse/ClickHouse/pull/99840))
- `VALUES (...) AS t(col, ...)` — `FROM` 절에서 사용 가능한 SQL 표준 `VALUES` ([#100143](https://github.com/ClickHouse/ClickHouse/pull/100143))

**테스트 내용:**
- `SELECT` 소스, CTE 내부, JOIN 오른편으로 `VALUES` 사용
- 단일 공통 컬럼 NATURAL JOIN
- `JOIN ... ON`과 컬럼 수 비교
- `VALUES`만으로 구성된 NATURAL JOIN
- 국가코드 룩업 패턴 (temp 테이블 대체)
- 다중 컬럼 NATURAL JOIN

#### 2. `arrayTranspose` + `arrayAutocorrelation`

- `arrayTranspose(matrix)` — 2-D 배열 행/열 전치 ([#101214](https://github.com/ClickHouse/ClickHouse/pull/101214))
- `arrayAutocorrelation(arr [, max_lag])` — 각 lag별 정규화 자기상관 ([#94776](https://github.com/ClickHouse/ClickHouse/pull/94776))

**테스트 내용:**
- 2×3 → 3×2, 정사각, 단일 행 → 열 벡터
- `arrayTranspose(arrayTranspose(M)) = M` 항등식
- 행 단위 레코드 → 열 단위 필드 피벗
- 선형 증가, 상수, 랜덤 노이즈의 자기상관
- 28일 합성 시계열에서 주간(7일) 계절성 탐지
- 사용자 정의 `max_lag` 파라미터
- 결합 사용: 신호 스택 전치 후 신호별 자기상관

#### 3. `obfuscateQuery` + `highlight` + 비상수 `printf`

- `obfuscateQuery(s)` — 식별자/리터럴을 결정론적 임의값으로 교체 (SQL 구조 보존) ([#98305](https://github.com/ClickHouse/ClickHouse/pull/98305))
- `highlight(text, terms [, open, close])` — 각 일치 항목을 HTML 태그로 감싸기 (기본 `<em>`) ([#99131](https://github.com/ClickHouse/ClickHouse/pull/99131))
- `printf` 비상수 포맷 문자열 — 행별 다른 포맷 ([#98991](https://github.com/ClickHouse/ClickHouse/pull/98991))

**테스트 내용:**
- 단순/복합 SQL의 `obfuscateQuery`
- 결정론 확인 (동일 입력 → 동일 출력)
- 3개 쿼리 일괄 난독화
- 기본/사용자 정의 태그, 대소문자 구분 없는 매칭
- 실제 기사 본문에 `highlight` 적용한 검색 결과 파이프라인
- 행별 포맷 문자열 (decimal, hex, octal, zero-padded)
- 혼합 포맷 로깅 출력
- 결합 파이프라인: 필터 → 하이라이트 → 포맷팅

### 🆕 26.4의 새로운 기능

- **자동 JOIN 스필링** — 메모리 한도 도달 시 grace hash join 자동 전환 (기본 동작)
- **Arrow Flight SQL** 지원
- **`NATURAL JOIN`** 구문
- **`VALUES`** FROM 절 테이블 표현식
- **`arrayTranspose`, `arrayAutocorrelation`**
- **`obfuscateQuery`, `highlight`, 비상수 `printf`**
- **PostgreSQL 호환 `EXTRACT` 단위** — `EPOCH`, `DOW`, `DOY`, `ISODOW`, `ISOYEAR`, `WEEK`, `CENTURY`, `DECADE`, `MILLENNIUM`
- **SQL 표준 복합 인터벌** — `INTERVAL '1:30' HOUR TO MINUTE`
- **`hasPhrase` / `matchPhrase`** — 연속 토큰 시퀀스 검색
- **`commit_order` 프로젝션 인덱스** — 삽입 순서 유지
- **JSON 컬럼 MergeTree 스킵 인덱스** — `bloom_filter`, `tokenbf_v1`, `ngrambf_v1`, `text` on `JSONAllPaths`
- **Map 컬럼 버킷 직렬화** — 단일 키 조회 2~49배 가속
- **`stem` 함수 GA**
- **딕셔너리 속성에 Map/JSON 지원**
- **`auto_statistics_types`** 기본값 `'minmax, uniq'`
- **`Date + Time`** → `DateTime`/`DateTime64`
- **정규화 쿼리 해시별 쿼터** — 쿼리 패턴별 제한
- **`SET TIME ZONE`** — `SET session_timezone` 별칭
- **Text 인덱스 GA** — `compatibility` 설정 무관 활성 유지
- **실험적 `aiGenerate`** 함수 — SQL에서 OpenAI/Anthropic LLM 호출

### 🔍 추가 자료

- **Release Presentation**: [ClickHouse 26.4](https://presentations.clickhouse.com/2026-release-26.4/)
- **Release Video**: [YouTube](https://www.youtube.com/watch?v=9lSVy7k2EoI)

### 📝 참고사항

- 모든 기능은 ClickHouse 26.4.3에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 정리(cleanup)는 기본적으로 주석 처리됨

---

**Happy Learning! 🚀**
