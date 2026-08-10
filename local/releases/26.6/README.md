# ClickHouse 26.6 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.6 new features. This directory focuses on verified and working features newly added in ClickHouse 26.6 (released 2026-06-25, the 10-year anniversary release with 56 new features, 79 performance optimizations and 366 bug fixes).

### 📋 Overview

ClickHouse 26.6 makes index tuning measurable and schema changes cheap. `CREATE HYPOTHETICAL INDEX` plus `EXPLAIN WHATIF` price a skip-index candidate before you pay to build it, `ADD ENUM VALUES` turns an Enum extension into an append instead of a whole-type rewrite, and a batch of ANSI/PostgreSQL syntax — `SOME`/`ALL` quantifiers, column selection by pattern, `LIKE ... ESCAPE`, `date_part` — closes long-standing porting gaps.

### 🎯 Key Features

1. **Hypothetical Indexes + `EXPLAIN WHATIF`** — estimate a skip index's benefit without building it
2. **`ALTER TABLE ... ADD ENUM VALUES`** — append Enum members without restating the existing ones
3. **SQL Compatibility and Ergonomics** — `SOME`/`ALL`, `* LIKE`/`* ILIKE`, `LIKE ... ESCAPE`, `date_part`/`EXTRACT`, compatibility aliases, `system.documentation`

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/26.6
./00-setup.sh

./01-hypothetical-indexes.sh
./02-add-enum-values.sh
./03-sql-compatibility.sh
```

### 📚 Feature Details

#### 1. Hypothetical Indexes + `EXPLAIN WHATIF` (01-hypothetical-indexes)

**New Feature:** `CREATE HYPOTHETICAL INDEX <name> ON <table> (<expr>) TYPE <type> GRANULARITY <n>` registers a skip-index *candidate* that is never built and never written to disk. `EXPLAIN WHATIF <query>` then reports, per candidate, how many marks and bytes the query would read and the resulting `skip_ratio`. ([Release blog](https://clickhouse.com/blog/clickhouse-release-26-06))

**Test Content:**
- A 1M-row table with three deliberately different distributions (clustered, uniformly spread, key-correlated)
- `EXPLAIN WHATIF` with no candidate defined — baseline only, with a hint
- A `set(4)` candidate on a clustered column → 87% skip
- Three candidates (`set`, `minmax`, `bloom_filter`) compared in a single report
- `system.hypothetical_indexes` inventory
- Clustered vs uniformly spread rare values: 99.2% vs 0.8% skip for the *same* index type
- `not_applicable` verdicts with the reason
- `DROP HYPOTHETICAL INDEX`
- Proof that `SHOW CREATE TABLE` and `system.data_skipping_indices` never changed
- Materializing the winner with `ADD INDEX` + `MATERIALIZE INDEX` and confirming that `EXPLAIN indexes = 1` reports the granule count WHATIF predicted

**Key Learning Points:**
- Hypothetical indexes are **session-scoped**: they live only inside the connection that created them, which is why the whole lab must run in one `clickhouse-client` invocation
- `EXPLAIN WHATIF` prints the baseline (after primary key, partition and existing indexes) first, then one block per candidate
- The estimate is empirical — ClickHouse reads table data to build the candidate in memory, so the scan counts against the session's read limits and quotas
- Rarity does not make a value indexable: a value appearing every 1,000 rows lands in every granule, so `skip_ratio` stays near zero
- `not_applicable` is reported with a reason instead of the candidate being silently dropped
- The predicted mark count matches the granule count of the real index once materialized

**Use Cases:**
- Choosing between skip-index candidates without a build-benchmark-drop cycle
- Justifying (or rejecting) an index request with numbers before touching production DDL
- Teaching why data distribution, not cardinality alone, decides index value
- Auditing whether existing indexes still earn their storage

---

#### 2. `ALTER TABLE ... ADD ENUM VALUES` (02-add-enum-values)

**New Feature:** `ALTER TABLE <t> MODIFY COLUMN <col> ADD ENUM VALUES('name' = id, ...)` appends members to an existing `Enum8`/`Enum16` without restating the values it already has. Ids may be omitted, in which case they continue from `max(id) + 1`. ([Release blog](https://clickhouse.com/blog/clickhouse-release-26-06))

**Test Content:**
- A 200k-row table with a three-value event taxonomy
- The pre-26.6 way: `MODIFY COLUMN` restating every value (still valid)
- The new way: appending a single member
- Auto-assigned ids
- Appending several members in one statement
- Verifying the original rows read back unchanged, then inserting rows that use the new members
- `Enum16` for sparse code taxonomies (HTTP-status style)
- `Nullable(Enum8)`
- Ordering semantics: `ORDER BY` on an Enum sorts by id, so appended values sort last

**Key Learning Points:**
- The append is metadata-only — existing parts are not rewritten
- Omitting `= N` appends at `max(id) + 1`; explicit ids may leave gaps (`5, 6, 10, 11, 12`)
- Works the same on `Enum16` and on `Nullable(Enum8)`
- `ORDER BY enum_col` sorts by the numeric id, not the name — cast with `toString()` for alphabetical order
- Restating the whole type still works, which matters for migrations that must run on older servers too

**Use Cases:**
- Growing event/status taxonomies in append-only fashion
- Migrations that previously risked dropping a value while retyping a long Enum
- Keeping `Enum` (compact, ordered) instead of retreating to `LowCardinality(String)` just because the set changes
- Adding error codes to an `Enum16` without a full-column rewrite

---

#### 3. SQL Compatibility and Ergonomics (03-sql-compatibility)

**New Features:**
- `SOME` / `ALL` quantified comparisons over arrays and subqueries
- Column selection by pattern: `SELECT * LIKE 'ts_%'`, `SELECT * ILIKE 'ORDER%'`
- `ESCAPE` clause for `LIKE`
- PostgreSQL-style `date_part('unit', value)` alongside ANSI `EXTRACT(unit FROM value)`
- Compatibility aliases `min_by`, `max_by`, `REGEXP_SUBSTR`
- `system.documentation` — the reference docs embedded in the server, behind the CLI `help` command

([Release blog](https://clickhouse.com/blog/clickhouse-release-26-06))

**Test Content:**
- `SOME`/`ALL` over arrays, with the `arrayAll`/`arrayExists` equivalents side by side
- `SOME`/`ALL` over subqueries ("larger than every ap-south order")
- `* LIKE` / `* ILIKE`, composed with `EXCEPT (col)` and `APPLY max`
- `LIKE 'ORDER!_%' ESCAPE '!'` matching a literal underscore, and rejecting other characters
- `date_part` and `EXTRACT` for year/month/day/hour/minute/quarter, plus a grouped daily report
- `min_by`/`max_by` next to native `argMin`/`argMax`, and `REGEXP_SUBSTR`
- A per-region report combining the new syntax
- `system.documentation`: entity counts by type, a single-function lookup, and a full-text search over the docs

**Key Learning Points:**
- `x > ALL(...)` / `x > SOME(...)` accept both array literals and subqueries
- `* LIKE` / `* ILIKE` select columns by name pattern; only `LIKE` and `ILIKE` are supported (`* NOT LIKE` is not, and regex column selection remains `COLUMNS('...')`)
- Column patterns compose with the existing `EXCEPT` and `APPLY` modifiers
- `ESCAPE` nominates a character that turns off `_`/`%` wildcard meaning for the next character
- `date_part` and `EXTRACT` are two spellings of one operation, so ported reports can keep their original form
- `min_by`/`max_by` are aliases of `argMin`/`argMax` — same semantics, familiar name
- `system.documentation` carries ~1,600 documented functions plus settings, formats and engines, searchable from SQL

**Use Cases:**
- Porting Postgres/Snowflake reports with fewer rewrites
- Querying wide tables by column-name convention (`ts_*`, `dim_*`) instead of listing columns
- Matching identifiers that legitimately contain `_` or `%`
- Discovering functions and settings without leaving the session

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
docker logs clickhouse-26-6
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.6/
├── README.md                          # This document
├── 00-setup.sh                        # ClickHouse 26.6 installation script
├── 01-hypothetical-indexes.sh         # Hypothetical index runner
├── 01-hypothetical-indexes.sql        # Hypothetical index SQL
├── 02-add-enum-values.sh              # ADD ENUM VALUES runner
├── 02-add-enum-values.sql             # ADD ENUM VALUES SQL
├── 03-sql-compatibility.sh            # SQL compatibility runner
└── 03-sql-compatibility.sql           # SQL compatibility SQL
```

### 🆕 What's New in 26.6

- **Hypothetical skip indexes** — `CREATE HYPOTHETICAL INDEX` + `EXPLAIN WHATIF`
- **`ALTER TABLE ... ADD ENUM VALUES`**
- **Cascading refreshable materialized views** — `REFRESH DEPENDS ON`, dependency-driven instead of independent timers
- **CLI `help` command** backed by the new **`system.documentation`** table
- **clickhouse-local server mode** — `SYSTEM START/STOP LISTEN TCP/HTTP`
- **Continuous queries** (experimental) — `SELECT ... FROM <table> STREAM`
- **Schema Visualizer** in the web UI — dependency graph of tables, materialized views and dictionaries
- **`PNG` output format** — render query results as an image
- **`GeoJSON` input format** and **MVT functions** (`MVTEncodeGeom`, `MVTEncode`, `MVTBoundingBox`)
- **`aiEmbed`** (experimental) — embeddings via a configured AI provider
- **Quantization functions** — `quantizeBFloat16ToInt8`, `dequantizeInt8ToBFloat16`
- **Memory reservations for workloads** — `CREATE RESOURCE memory (MEMORY RESERVATION)`
- **`SOME` / `ALL` array quantifiers**
- **Column selection by pattern** — `SELECT * LIKE / * ILIKE`
- **`ESCAPE` clause for `LIKE`**
- **PostgreSQL-style `date_part()`** alongside `EXTRACT`
- **Compatibility aliases** — `min_by`, `max_by`, `REGEXP_SUBSTR`
- **Multi-stage distributed query execution** (experimental)
- **3x lower latency on deeply nested queries**

### 🔍 Additional Resources

- **Release Blog**: [ClickHouse Release 26.6](https://clickhouse.com/blog/clickhouse-release-26-06)
- **Release Presentation**: [ClickHouse 26.6](https://presentations.clickhouse.com/2026-release-26.6/)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 26.6.2
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- `01-hypothetical-indexes.sql` must run as a single session — hypothetical indexes disappear when the connection closes
- `EXPLAIN WHATIF` reads real data to produce its estimate, so expect a few seconds on the 1M-row table


### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 26.6 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 6월 25일 출시된 ClickHouse 26.6에서 검증된 작동 기능에 집중합니다. 26.6은 10주년 기념 릴리스로 신기능 56건, 성능 최적화 79건, 버그 수정 366건을 포함합니다.

### 📋 개요

ClickHouse 26.6은 인덱스 튜닝을 측정 가능하게 만들고 스키마 변경 비용을 낮춥니다. `CREATE HYPOTHETICAL INDEX`와 `EXPLAIN WHATIF`로 스킵 인덱스 후보를 만들기 전에 효과를 산정하고, `ADD ENUM VALUES`는 Enum 확장을 전체 타입 재작성이 아닌 추가(append)로 바꿉니다. 여기에 `SOME`/`ALL` 수량자, 패턴 기반 컬럼 선택, `LIKE ... ESCAPE`, `date_part` 등 ANSI/PostgreSQL 구문이 이식 시의 간극을 메웁니다.

### 🎯 주요 기능

1. **가상 인덱스 + `EXPLAIN WHATIF`** — 인덱스를 만들지 않고 효과를 산정
2. **`ALTER TABLE ... ADD ENUM VALUES`** — 기존 값을 다시 나열하지 않고 Enum 멤버 추가
3. **SQL 호환성과 사용성** — `SOME`/`ALL`, `* LIKE`/`* ILIKE`, `LIKE ... ESCAPE`, `date_part`/`EXTRACT`, 호환 별칭, `system.documentation`

### 🚀 빠른 시작

```bash
cd local/releases/26.6
./00-setup.sh

./01-hypothetical-indexes.sh
./02-add-enum-values.sh
./03-sql-compatibility.sh
```

### 📚 기능 상세

#### 1. 가상 인덱스 + `EXPLAIN WHATIF`

`CREATE HYPOTHETICAL INDEX <이름> ON <테이블> (<식>) TYPE <타입> GRANULARITY <n>`은 실제로 만들지도, 디스크에 쓰지도 않는 스킵 인덱스 **후보**를 등록합니다. 이후 `EXPLAIN WHATIF <쿼리>`가 후보별로 읽게 될 mark 수·바이트와 `skip_ratio`를 보고합니다. ([릴리스 블로그](https://clickhouse.com/blog/clickhouse-release-26-06))

**테스트 내용:**
- 서로 다른 3가지 분포(군집형, 균일 분산형, 키 상관형)를 가진 100만 행 테이블
- 후보가 없는 상태의 `EXPLAIN WHATIF` — baseline과 안내 메시지
- 군집형 컬럼에 `set(4)` 후보 → 87% skip
- `set`/`minmax`/`bloom_filter` 세 후보를 한 번에 비교
- `system.hypothetical_indexes` 목록
- 같은 인덱스 타입에서 군집형 vs 균일 분산형 희귀값: 99.2% vs 0.8% skip
- 사유가 붙은 `not_applicable` 판정
- `DROP HYPOTHETICAL INDEX`
- `SHOW CREATE TABLE`과 `system.data_skipping_indices`가 전혀 변하지 않았음을 확인
- 승자를 `ADD INDEX` + `MATERIALIZE INDEX`로 실제 생성한 뒤, `EXPLAIN indexes = 1`의 granule 수가 WHATIF 예측과 일치하는지 확인

**핵심 학습 포인트:**
- 가상 인덱스는 **세션 범위**입니다 — 생성한 커넥션 안에서만 존재하므로 이 랩 전체가 하나의 `clickhouse-client` 실행으로 돌아가야 합니다
- `EXPLAIN WHATIF`는 baseline(주 키·파티션·기존 인덱스 적용 후)을 먼저 출력하고 이어서 후보별 블록을 출력합니다
- 산정은 경험적(empirical)입니다 — 후보 인덱스를 메모리에 만들기 위해 실제 데이터를 읽으므로 세션의 read 제한·쿼터에 집계됩니다
- 희귀하다고 인덱스가 되는 것은 아닙니다: 1,000행마다 등장하는 값은 모든 granule에 들어가므로 `skip_ratio`가 0에 가깝습니다
- 적용 불가 후보는 조용히 빠지지 않고 사유와 함께 `not_applicable`로 보고됩니다
- 예측된 mark 수는 실제 인덱스를 만든 뒤의 granule 수와 일치합니다

#### 2. `ALTER TABLE ... ADD ENUM VALUES`

`ALTER TABLE <t> MODIFY COLUMN <col> ADD ENUM VALUES('이름' = id, ...)`는 기존 값을 다시 나열하지 않고 `Enum8`/`Enum16`에 멤버를 추가합니다. id를 생략하면 `max(id) + 1`부터 이어서 부여됩니다. ([릴리스 블로그](https://clickhouse.com/blog/clickhouse-release-26-06))

**테스트 내용:**
- 3개 값 이벤트 분류를 가진 20만 행 테이블
- 26.6 이전 방식: 모든 값을 다시 나열하는 `MODIFY COLUMN` (여전히 유효)
- 새 방식: 멤버 하나만 추가
- id 자동 부여
- 한 문장에서 여러 멤버 추가
- 기존 행이 그대로 읽히는지 확인한 뒤 새 멤버를 사용한 INSERT
- 희소한 코드 분류를 위한 `Enum16` (HTTP 상태 코드 형태)
- `Nullable(Enum8)`
- 정렬 의미: Enum의 `ORDER BY`는 id 기준이므로 추가된 값이 마지막에 정렬됨

**핵심 학습 포인트:**
- 추가는 메타데이터 전용 작업입니다 — 기존 파트는 재작성되지 않습니다
- `= N`을 생략하면 `max(id) + 1`에 추가되고, 명시적 id는 간격을 남길 수 있습니다 (`5, 6, 10, 11, 12`)
- `Enum16`, `Nullable(Enum8)`에서도 동일하게 동작합니다
- `ORDER BY enum_col`은 이름이 아니라 숫자 id로 정렬합니다 — 알파벳 순서가 필요하면 `toString()`으로 캐스팅하세요
- 전체 타입 재작성 방식도 계속 동작하므로, 구버전 서버에서도 실행돼야 하는 마이그레이션에 유용합니다

#### 3. SQL 호환성과 사용성

- 배열과 서브쿼리에 대한 `SOME` / `ALL` 수량 비교
- 패턴 기반 컬럼 선택: `SELECT * LIKE 'ts_%'`, `SELECT * ILIKE 'ORDER%'`
- `LIKE`의 `ESCAPE` 절
- PostgreSQL 스타일 `date_part('unit', value)`와 ANSI `EXTRACT(unit FROM value)`
- 호환 별칭 `min_by`, `max_by`, `REGEXP_SUBSTR`
- `system.documentation` — 서버에 내장된 레퍼런스 문서, CLI `help` 명령의 백엔드

**테스트 내용:**
- 배열에 대한 `SOME`/`ALL`과 `arrayAll`/`arrayExists` 대응 비교
- 서브쿼리에 대한 `SOME`/`ALL` ("모든 ap-south 주문보다 큰 주문")
- `* LIKE` / `* ILIKE`, `EXCEPT (col)` 및 `APPLY max`와의 조합
- `LIKE 'ORDER!_%' ESCAPE '!'`로 리터럴 밑줄 매칭, 다른 문자는 거부
- year/month/day/hour/minute/quarter에 대한 `date_part`와 `EXTRACT`, 그리고 일자별 집계 리포트
- `min_by`/`max_by`와 네이티브 `argMin`/`argMax` 비교, `REGEXP_SUBSTR`
- 새 구문을 결합한 지역별 리포트
- `system.documentation`: 타입별 엔티티 수, 함수 단건 조회, 문서 전문 검색

**핵심 학습 포인트:**
- `x > ALL(...)` / `x > SOME(...)`은 배열 리터럴과 서브쿼리를 모두 받습니다
- `* LIKE` / `* ILIKE`는 이름 패턴으로 컬럼을 고릅니다. 지원되는 것은 `LIKE`와 `ILIKE`뿐이며(`* NOT LIKE`는 불가), 정규식 컬럼 선택은 기존 `COLUMNS('...')`입니다
- 컬럼 패턴은 기존 `EXCEPT`, `APPLY` 수정자와 조합됩니다
- `ESCAPE`는 다음 문자의 `_`/`%` 와일드카드 의미를 해제하는 문자를 지정합니다
- `date_part`와 `EXTRACT`는 같은 연산의 두 표기이므로 이식된 리포트를 원형 그대로 유지할 수 있습니다
- `min_by`/`max_by`는 `argMin`/`argMax`의 별칭입니다 — 의미는 같고 이름만 친숙해집니다
- `system.documentation`에는 함수 약 1,600건과 설정·포맷·엔진 문서가 들어 있어 SQL로 검색할 수 있습니다

### 🆕 26.6의 새로운 기능

- **가상 스킵 인덱스** — `CREATE HYPOTHETICAL INDEX` + `EXPLAIN WHATIF`
- **`ALTER TABLE ... ADD ENUM VALUES`**
- **연쇄 갱신 구체화 뷰** — `REFRESH DEPENDS ON`, 독립 타이머 대신 의존성 기반 갱신
- **CLI `help` 명령** — 신규 **`system.documentation`** 테이블 기반
- **clickhouse-local 서버 모드** — `SYSTEM START/STOP LISTEN TCP/HTTP`
- **연속 쿼리** (실험적) — `SELECT ... FROM <테이블> STREAM`
- **Schema Visualizer** 웹 UI — 테이블·구체화 뷰·딕셔너리 의존성 그래프
- **`PNG` 출력 포맷** — 쿼리 결과를 이미지로 렌더링
- **`GeoJSON` 입력 포맷**과 **MVT 함수** (`MVTEncodeGeom`, `MVTEncode`, `MVTBoundingBox`)
- **`aiEmbed`** (실험적) — 설정된 AI 제공자를 통한 임베딩 생성
- **양자화 함수** — `quantizeBFloat16ToInt8`, `dequantizeInt8ToBFloat16`
- **워크로드 메모리 예약** — `CREATE RESOURCE memory (MEMORY RESERVATION)`
- **`SOME` / `ALL` 배열 수량자**
- **패턴 기반 컬럼 선택** — `SELECT * LIKE / * ILIKE`
- **`LIKE`의 `ESCAPE` 절**
- **PostgreSQL 스타일 `date_part()`** 와 `EXTRACT`
- **호환 별칭** — `min_by`, `max_by`, `REGEXP_SUBSTR`
- **다단계 분산 쿼리 실행** (실험적)
- **깊게 중첩된 쿼리 지연 3배 감소**

### 🔍 추가 자료

- **Release Blog**: [ClickHouse Release 26.6](https://clickhouse.com/blog/clickhouse-release-26-06)
- **Release Presentation**: [ClickHouse 26.6](https://presentations.clickhouse.com/2026-release-26.6/)
- **Changelog**: [docs.clickhouse.com/whats-new/changelog](https://clickhouse.com/docs/whats-new/changelog)

### 📝 참고사항

- 모든 기능은 ClickHouse 26.6.2에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- `01-hypothetical-indexes.sql`은 반드시 단일 세션으로 실행해야 합니다 — 커넥션이 닫히면 가상 인덱스는 사라집니다
- `EXPLAIN WHATIF`는 실제 데이터를 읽어 산정하므로 100만 행 테이블에서 수 초가 걸릴 수 있습니다


### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**
