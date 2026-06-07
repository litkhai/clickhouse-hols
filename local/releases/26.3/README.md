# ClickHouse 26.3 LTS New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.3 LTS new features. This directory focuses on verified and working features newly added in ClickHouse 26.3 (released 2026-03-26, the second LTS release of 2026).

### 📋 Overview

ClickHouse 26.3 is an **LTS release** that tightens SQL ergonomics: CTEs can now be materialized once and reused, a new `naturalSortKey` makes "file2 / file10" sort the way humans expect, and a family of Unicode normalization functions unlocks robust language-aware text matching.

### 🎯 Key Features Covered

1. **Materialized CTE** — `WITH cte AS MATERIALIZED (...)` and `enable_materialized_cte` setting
2. **`naturalSortKey()` Function** — human-friendly mixed-letter/number sorting
3. **Unicode Functions** — `caseFoldUTF8`, `removeDiacriticsUTF8`, `normalizeUTF8NFKCCasefold`

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/26.3
./00-setup.sh

./01-materialized-cte.sh
./02-natural-sort-key.sh
./03-unicode-functions.sh
```

### 📚 Feature Details

#### 1. Materialized CTE (01-materialized-cte)

**New Feature:** Common Table Expressions can be evaluated once and stored in a temporary table, instead of being inlined at every reference. ([#94849](https://github.com/ClickHouse/ClickHouse/pull/94849))

**Two ways to opt in:**
- Inline: `WITH cte AS MATERIALIZED (...)` — explicit, per-CTE
- Setting: `SET enable_materialized_cte = 1` — applies to bare `WITH ... AS ...` CTEs referenced more than once

**Test Content:**
- Basic `AS MATERIALIZED` syntax
- CTE referenced in 3-way self-join (would re-execute 3× without materialization)
- `EXPLAIN PIPELINE` side-by-side comparison
- Reused aggregation (`category_totals` used twice)
- CTE with window function
- Setting-driven materialization

**Key Learning Points:**
- Materialized CTEs trade memory for CPU — useful when the CTE is expensive and reused
- Inline `AS MATERIALIZED` keyword overrides the session setting
- Plan inspection via `EXPLAIN PIPELINE` shows the source is scanned once
- Default behavior (inline) is preserved when CTE is referenced only once

**Use Cases:**
- Expensive aggregations referenced multiple times in the same query
- Window-function results reused in self-joins
- Reducing repeated remote-table scans in distributed queries

---

#### 2. `naturalSortKey()` Function (02-natural-sort-key)

**New Feature:** `naturalSortKey(s)` produces a binary key that, when used as the `ORDER BY` expression, sorts strings in human-friendly "natural" order — digit runs are compared numerically, so `file2 < file10`. ([#90322](https://github.com/ClickHouse/ClickHouse/pull/90322))

**Test Content:**
- Demonstration of the lexical-vs-natural difference
- Inspecting the raw `naturalSortKey` output (hex)
- Software version strings (`25.5` vs `25.10`)
- Filename-style mixed content
- Using `naturalSortKey` as a `MATERIALIZED` column in a MergeTree `ORDER BY` clause
- Mixed-case identifiers

**Key Learning Points:**
- Use as the `ORDER BY` expression, not as a comparison operator
- Can be stored as a `MATERIALIZED` column for indexed natural ordering
- The output is a binary string, not human-readable — only its sort order matters
- Letters are still compared by codepoint (case-sensitive), only digits get special treatment

**Use Cases:**
- Filename listings (`log-1.txt … log-100.txt`)
- Software version sorting (`25.5 → 25.6 → 25.10 → 26.1`)
- Chapter / episode lists
- Build identifiers and SKUs with mixed letters and numbers

---

#### 3. Unicode Normalization Functions (03-unicode-functions)

**New Features:** Three new functions for Unicode-aware text canonicalization:

- `caseFoldUTF8(s)` — locale-independent Unicode case folding (handles ß, İ, ẞ, Greek, etc.) ([#98973](https://github.com/ClickHouse/ClickHouse/pull/98973))
- `removeDiacriticsUTF8(s)` — strips combining marks (`café` → `cafe`, `naïve` → `naive`)
- `normalizeUTF8NFKCCasefold(s)` — NFKC compatibility normalization + case folding in one pass ([#99276](https://github.com/ClickHouse/ClickHouse/pull/99276))

**Test Content:**
- `caseFoldUTF8` vs `lower()` on German, Turkish, Greek text
- Accent stripping across French, Spanish, Czech, Polish examples
- NFKC compatibility: full-width Latin, ligatures, circled digits, compatibility characters (`㎏ → kg`)
- Search-friendly `MATERIALIZED` column combining all three
- Duplicate-name detection by normalized key
- Side-by-side comparison table

**Key Learning Points:**
- `caseFoldUTF8` is the right answer for international case-insensitive comparison; `lower()` is ASCII-biased
- `removeDiacriticsUTF8` does NOT lowercase — combine with `caseFoldUTF8` for full normalization
- `normalizeUTF8NFKCCasefold` is the most aggressive — it merges compatibility variants like `㎏ → kg`, `Ⅷ → viii`
- Common pattern: store `removeDiacriticsUTF8(normalizeUTF8NFKCCasefold(name))` as a `MATERIALIZED` column for fuzzy name matching

**Use Cases:**
- Case-insensitive search across multilingual content
- Fuzzy name matching (CRM, identity resolution, deduplication)
- Search indexes that should match `José`, `JOSE`, `Jose`, `jose`, `josé` interchangeably
- Cleaning OCR / mixed-encoding text

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
docker logs clickhouse-26-3
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.3/
├── README.md                     # This document
├── 00-setup.sh                   # ClickHouse 26.3 LTS installation script
├── 01-materialized-cte.sh        # Materialized CTE test runner
├── 01-materialized-cte.sql       # Materialized CTE SQL
├── 02-natural-sort-key.sh        # naturalSortKey test runner
├── 02-natural-sort-key.sql       # naturalSortKey SQL
├── 03-unicode-functions.sh       # Unicode functions test runner
└── 03-unicode-functions.sql      # Unicode functions SQL
```

### 🆕 What's New in 26.3 LTS

- **Materialized CTE** with `AS MATERIALIZED` and `enable_materialized_cte`
- **`naturalSortKey()`** for human-friendly mixed-content sorting
- **`caseFoldUTF8`, `removeDiacriticsUTF8`, `normalizeUTF8NFKCCasefold`** — Unicode normalization
- **`mergeTreeTextIndex()` table function** — read text-index contents directly
- **Bucketed Map serialization** — 2-49× faster single-key lookups on Map columns
- **`pretty = 1` / `compact = 1` EXPLAIN options** — tree-style and collapsed plans
- **`NOW` (and other zero-arg functions) without parentheses** — SQL-standard compatibility
- **`SOME` keyword** — alias for `ANY` in subquery expressions
- **`asciiCJK` tokenizer** — Unicode word-boundary tokenization for full-text indexes
- **`toDaysInMonth()`** — number of days in the month of a date
- **`table_readonly` MergeTree setting** — mark tables as read-only
- **Experimental WebAssembly UDFs** and **`ALP` floating-point compression codec**
- **Experimental lazy JSON type hints** — metadata-only `MODIFY COLUMN`

### 🔍 Additional Resources

- **Release Video**: [YouTube](https://www.youtube.com/watch?v=_bY0ucNB1lQ)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2026](https://clickhouse.com/docs/whats-new/changelog)

### 📝 Notes

- 26.3 is the **LTS** release for 2026 — supported for 1 year vs. 6 months for stable
- All features verified on ClickHouse 26.3.12
- Each script runs independently; cleanup is commented out for inspection

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse 26.3 LTS 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 3월 26일 출시된 LTS 릴리스 ClickHouse 26.3에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 26.3은 **LTS 릴리스**로, SQL 사용성을 강화합니다: CTE를 한 번 평가해 재사용할 수 있고, 새로운 `naturalSortKey`로 `file2 / file10`을 사람이 기대하는 순서로 정렬하며, 유니코드 정규화 함수군으로 다국어 텍스트 매칭이 견고해집니다.

### 🎯 주요 다루는 기능

1. **Materialized CTE** — `WITH cte AS MATERIALIZED (...)` 및 `enable_materialized_cte` 설정
2. **`naturalSortKey()` 함수** — 사람 친화적인 문자/숫자 혼합 정렬
3. **Unicode 함수들** — `caseFoldUTF8`, `removeDiacriticsUTF8`, `normalizeUTF8NFKCCasefold`

### 🚀 빠른 시작

```bash
cd local/releases/26.3
./00-setup.sh

./01-materialized-cte.sh
./02-natural-sort-key.sh
./03-unicode-functions.sh
```

### 📚 기능 상세

#### 1. Materialized CTE

CTE를 한 번 평가해 임시 테이블에 저장하고 모든 참조에서 재사용합니다. ([#94849](https://github.com/ClickHouse/ClickHouse/pull/94849))

**두 가지 활성화 방법:**
- 인라인: `WITH cte AS MATERIALIZED (...)`
- 설정: `SET enable_materialized_cte = 1` (`WITH ... AS ...`가 두 번 이상 참조될 때)

**테스트 내용:**
- 기본 `AS MATERIALIZED` 구문
- 3-way self-join에서 참조된 CTE
- `EXPLAIN PIPELINE` 비교
- 재사용되는 집계 (`category_totals`)
- 윈도우 함수와 CTE
- 설정 기반 머터리얼라이제이션

#### 2. `naturalSortKey()` 함수

`naturalSortKey(s)`는 `ORDER BY` 표현식으로 사용 시 사람 친화적 자연 정렬을 만드는 바이너리 키를 반환합니다 (숫자 부분은 숫자로 비교). ([#90322](https://github.com/ClickHouse/ClickHouse/pull/90322))

**테스트 내용:**
- 사전식 vs 자연 정렬 차이 시연
- 원본 키(hex) 검사
- 소프트웨어 버전 문자열
- 파일명 스타일
- MergeTree `ORDER BY`에 `MATERIALIZED` 컬럼으로 저장
- 대소문자 혼합

#### 3. Unicode 정규화 함수

세 가지 새로운 함수:

- `caseFoldUTF8(s)` — 로케일 독립적 유니코드 케이스 폴딩 ([#98973](https://github.com/ClickHouse/ClickHouse/pull/98973))
- `removeDiacriticsUTF8(s)` — 발음 부호 제거 (`café` → `cafe`)
- `normalizeUTF8NFKCCasefold(s)` — NFKC 호환 정규화 + 케이스 폴딩 한 번에 ([#99276](https://github.com/ClickHouse/ClickHouse/pull/99276))

**테스트 내용:**
- 독일어, 터키어, 그리스어에서 `caseFoldUTF8` vs `lower()`
- 프랑스어, 스페인어, 체코어, 폴란드어 악센트 제거
- NFKC 호환성: 전각 라틴 문자, 합자, 동그라미 숫자, 호환 문자 (`㎏ → kg`)
- 세 함수를 결합한 검색용 `MATERIALIZED` 컬럼
- 정규화 키 기반 중복 이름 탐지
- 비교표

### 🆕 26.3 LTS의 새로운 기능

- **Materialized CTE** — `AS MATERIALIZED`와 `enable_materialized_cte`
- **`naturalSortKey()`** — 사람 친화적 혼합 정렬
- **`caseFoldUTF8`, `removeDiacriticsUTF8`, `normalizeUTF8NFKCCasefold`** — 유니코드 정규화
- **`mergeTreeTextIndex()` 테이블 함수** — 텍스트 인덱스 내용 직접 조회
- **버킷화된 Map 직렬화** — 단일 키 조회 2~49배 가속
- **`pretty = 1` / `compact = 1` EXPLAIN**
- **`NOW` 등 괄호 없는 호출** — SQL 표준 호환
- **`SOME` 키워드** — `ANY` 별칭
- **`asciiCJK` 토크나이저**
- **`toDaysInMonth()`**
- **`table_readonly` 설정**
- **실험적 WebAssembly UDF**, **`ALP` 부동소수 압축 코덱**, **JSON lazy 타입 힌트**

### 🔍 추가 자료

- **Release Video**: [YouTube](https://www.youtube.com/watch?v=_bY0ucNB1lQ)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)

### 📝 참고사항

- 26.3은 2026년 **LTS** 릴리스 (1년 지원)
- 모든 기능은 ClickHouse 26.3.12에서 검증
- 각 스크립트는 독립적으로 실행 가능

---

**Happy Learning! 🚀**
