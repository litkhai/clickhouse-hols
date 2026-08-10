# ClickHouse 26.7 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 26.7 new features. This directory focuses on verified and working features newly added in ClickHouse 26.7 (released 2026-07-22).

### 📋 Overview

ClickHouse 26.7 puts measurement and standard syntax front and centre: `EXPLAIN ANALYZE` runs a query and annotates every plan node with real rows, bytes, time share and parallelism; the ANSI `AT TIME ZONE` / `AT LOCAL` postfix operators land alongside `toTimeZone`; and aggregation gains `groupFormat` for serializing a group and the `-Tuple` combinator for element-wise aggregation over tuples.

### 🎯 Key Features

1. **`EXPLAIN ANALYZE`** — execute a query and read measured per-node counters
2. **`AT TIME ZONE` / `AT LOCAL`** — standard SQL postfix time zone operators
3. **`groupFormat` + `-Tuple` combinator** — serialize a group with any output format; aggregate tuples element-wise

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../../oss-mac-setup/) environment

#### Setup and Run

```bash
cd local/releases/26.7
./00-setup.sh

./01-explain-analyze.sh
./02-at-time-zone.sh
./03-groupformat-tuple.sh
```

### 📚 Feature Details

#### 1. `EXPLAIN ANALYZE` (01-explain-analyze)

**New Feature:** `EXPLAIN ANALYZE <query>` executes the query and prints the plan with measured counters on every node: rows in → out with selectivity, bytes, time share, parallelism, join algorithm with separate build/probe timings, and index/granule pruning. A summary header splits total time into planning and execution and reports rows read and peak memory. ([#106586](https://github.com/ClickHouse/ClickHouse/pull/106586), [#110668](https://github.com/ClickHouse/ClickHouse/pull/110668))

**Test Content:**
- A 2M-row fact table plus a small dimension table
- `EXPLAIN` (estimated plan) versus `EXPLAIN ANALYZE` (measured) on the same query
- Reading the summary header: planning vs execution time, rows read, peak memory
- Following selectivity (`rows N → M (P%)`) from the bottom of the plan upwards
- Primary key pruning: `Granules: 1/245` with `Search Algorithm: binary search`
- The same result set filtered on a non-key column — 8.19 thousand rows read vs 2.00 million
- Join internals: algorithm name, which side was built, and build vs probe timings
- A high-cardinality `GROUP BY` where the cost moves into the aggregation stages
- Two formulations of one question compared side by side (filter early vs filter late)

**Key Learning Points:**
- `EXPLAIN ANALYZE` **executes** the query — the numbers are real, so do not point it at statements with side effects
- The header's planning/execution split identifies plans that are expensive to build rather than to run
- Per-node `rows N → M (P%)` shows exactly where data volume collapses; the node that does not reduce rows is usually the one to fix
- `ReadFromMergeTree` reports parts, granules and the search algorithm, making key support or its absence obvious
- Join nodes name the algorithm (e.g. `SpillingHashJoin(HashJoin)`) and time build and probe separately, so a bad build side is visible immediately
- Time percentages are relative to execution, and `parallelism` shows how many threads a node actually used

**Use Cases:**
- Diagnosing a slow query without instrumenting the client or reading `system.query_log`
- Proving an optimization worked by comparing two `EXPLAIN ANALYZE` outputs
- Verifying that an index or ORDER BY key is actually being used
- Teaching query-plan reading with real numbers attached

---

#### 2. `AT TIME ZONE` / `AT LOCAL` (02-at-time-zone)

**New Feature:** the standard SQL postfix operators `<datetime> AT TIME ZONE '<tz>'` and `<datetime> AT LOCAL`. The first re-labels a value with the given time zone, the second uses the session's `session_timezone`. Both are equivalent to `toTimeZone()` and preserve `DateTime64` precision. ([#106092](https://github.com/ClickHouse/ClickHouse/pull/106092))

**Test Content:**
- One UTC instant rendered in Seoul, Paris and New York
- Type and epoch inspection: the type changes to `DateTime('Asia/Seoul')`, the Unix timestamp does not
- Equality with the `toTimeZone()` function form
- `AT LOCAL` under two different `session_timezone` settings
- Chained conversions, where the last operator wins
- `DateTime64(6)` keeping microseconds through the conversion
- A deploy log rendered simultaneously in three office time zones
- The classic reporting bug: a 23:30 UTC event belongs to the next calendar day in Seoul
- Filtering semantics — comparisons use the instant, so local-day filters must convert the boundary too

**Key Learning Points:**
- The operator changes the time zone *label*, not the instant: `toUnixTimestamp()` is unchanged before and after
- `toTypeName()` reflects the conversion (`DateTime('UTC')` → `DateTime('Asia/Seoul')`)
- `AT LOCAL` resolves against `session_timezone`, so the same query yields different output per session
- Sub-second precision survives: `DateTime64(6, 'UTC')` → `DateTime64(6, 'Asia/Seoul')`
- Grouping on a raw UTC value attributes late-evening events to the wrong local day — convert before `toDate()`
- Because comparisons operate on the instant, `WHERE ts AT TIME ZONE 'Asia/Seoul' >= '...'` filters identically to the unconverted form; convert the *boundary* for local-calendar filters

**Use Cases:**
- Porting Postgres/Snowflake/BigQuery reports that already use `AT TIME ZONE`
- Per-region dashboards rendering one event stream in several local times
- Correcting daily aggregates that silently used UTC day boundaries
- Keeping storage in UTC while presenting local time

---

#### 3. `groupFormat` + `-Tuple` Combinator (03-groupformat-tuple)

**New Features:**
- `groupFormat('<format>')(cols...)` — an aggregate that serializes the rows of each group using any ClickHouse output format, returning a single value ([#93201](https://github.com/ClickHouse/ClickHouse/pull/93201))
- `-Tuple` combinator — applies an aggregate element-wise to a `Tuple` argument, e.g. `sumTuple((a, b))` ([#98190](https://github.com/ClickHouse/ClickHouse/pull/98190))

**Test Content:**
- `groupFormat('CSV')` basics
- The same group as `TSV`, `JSONEachRow` and `Values`
- One payload per group with `GROUP BY` — per-device CSV exports
- A `JSONEachRow` payload per room, and the named-tuple trick for real JSON keys
- `sumTuple` / `avgTuple` / `minTuple` / `maxTuple` in a single pass, with the long-hand equivalent alongside
- Named tuples whose members stay addressable (`sumTuple(m).temp`)
- Stacking combinators: `sumTupleIf((a, b), predicate)`
- A combined report using both features

**Key Learning Points:**
- The format name is a **parameter** of `groupFormat`, the columns are its **arguments**: `groupFormat('CSV')(c1, c2)`
- Serialized columns are always labelled `c1`, `c2`, … — aliases and even `CSVWithNames` do not change that; wrap the arguments in a **named tuple** to get real keys into the payload
- `groupFormat` respects `GROUP BY`, so one query can build many independent payloads
- `-Tuple` replaces N repeated aggregates with one call and returns a tuple of the same arity
- Named tuple members survive aggregation and remain addressable by name
- Combinators compose — `sumTupleIf` applies both the tuple and the conditional behaviour

**Use Cases:**
- Building per-tenant or per-device export payloads directly in SQL
- Producing webhook/queue message bodies without an application-side serializer
- Aggregating coordinate or metric pairs (temp/humidity, lat/lon, min/max) in one pass
- Compact reports over tuple-shaped measurements

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
docker logs clickhouse-26-7
./stop.sh
./stop.sh --cleanup
```

### 📂 File Structure

```
26.7/
├── README.md                          # This document
├── 00-setup.sh                        # ClickHouse 26.7 installation script
├── 01-explain-analyze.sh              # EXPLAIN ANALYZE runner
├── 01-explain-analyze.sql             # EXPLAIN ANALYZE SQL
├── 02-at-time-zone.sh                 # AT TIME ZONE / AT LOCAL runner
├── 02-at-time-zone.sql                # AT TIME ZONE / AT LOCAL SQL
├── 03-groupformat-tuple.sh            # groupFormat + -Tuple runner
└── 03-groupformat-tuple.sql           # groupFormat + -Tuple SQL
```

### 🆕 What's New in 26.7

- **`EXPLAIN ANALYZE`** for query performance examination ([#106586](https://github.com/ClickHouse/ClickHouse/pull/106586), [#110668](https://github.com/ClickHouse/ClickHouse/pull/110668))
- **`WHERE` clauses in projection definitions** ([#102347](https://github.com/ClickHouse/ClickHouse/pull/102347))
- **`groupFormat`** aggregate function ([#93201](https://github.com/ClickHouse/ClickHouse/pull/93201))
- **`-Tuple` aggregate combinator** ([#98190](https://github.com/ClickHouse/ClickHouse/pull/98190))
- **`AT TIME ZONE` / `AT LOCAL`** postfix operators ([#106092](https://github.com/ClickHouse/ClickHouse/pull/106092))
- **`Remote` and `RemoteSecure` table engines** ([#106189](https://github.com/ClickHouse/ClickHouse/pull/106189))
- **`QueryRunner` table engine** ([#107888](https://github.com/ClickHouse/ClickHouse/pull/107888))
- **Engine-agnostic `SYSTEM STOP/START/PAUSE/CANCEL/REFRESH`** ([#107476](https://github.com/ClickHouse/ClickHouse/pull/107476))
- **`mysql` / `postgresql` / `sqlite` table functions accept user queries** ([#107740](https://github.com/ClickHouse/ClickHouse/pull/107740))
- **`WITH TIES` for negative `LIMIT`** ([#100930](https://github.com/ClickHouse/ClickHouse/pull/100930))
- **`GeoJSON` output format** ([#108065](https://github.com/ClickHouse/ClickHouse/pull/108065)) — the input side arrived in 26.6
- **UTM/MGRS conversions** — `geoToUTM`, `UTMToGeo`, `geoToMGRS`, `MGRSToGeo` ([#108939](https://github.com/ClickHouse/ClickHouse/pull/108939))
- **`geometryIntersectCartesian` / `geometryIntersectSpherical`** ([#110062](https://github.com/ClickHouse/ClickHouse/pull/110062))
- **`digits(n, offset[, length])`** ([#109012](https://github.com/ClickHouse/ClickHouse/pull/109012)) and **`sqr`** ([#109061](https://github.com/ClickHouse/ClickHouse/pull/109061))
- **`xxHash64Spark`** ([#108436](https://github.com/ClickHouse/ClickHouse/pull/108436))
- **`dotProductTransposed`** ([#108100](https://github.com/ClickHouse/ClickHouse/pull/108100)) and **`randomHadamardTransform`** ([#108227](https://github.com/ClickHouse/ClickHouse/pull/108227))
- **`QBit` stride parameter** ([#108103](https://github.com/ClickHouse/ClickHouse/pull/108103)) and **`Int8` element type** ([#108105](https://github.com/ClickHouse/ClickHouse/pull/108105))
- **Text index `postprocessor` argument** ([#98939](https://github.com/ClickHouse/ClickHouse/pull/98939), [#108606](https://github.com/ClickHouse/ClickHouse/pull/108606)) and **`system.stemmers`** ([#100611](https://github.com/ClickHouse/ClickHouse/pull/100611))
- **Naive Bayes as a `NAIVE_BAYES` dictionary layout** with `naiveBayesClassifierWithProb`, `naiveBayesClassifierWithAllProbs`, `naiveBayesNgrams` — ~49× less memory, ~11× faster load and classification
- **`SYSTEM UNLOAD DICTIONARY` / `DICTIONARIES`** ([#109639](https://github.com/ClickHouse/ClickHouse/pull/109639)), **per-dictionary lazy loading** ([#108314](https://github.com/ClickHouse/ClickHouse/pull/108314)), **`dictGetRoot`** ([#109459](https://github.com/ClickHouse/ClickHouse/pull/109459))
- **`ALTER USER` / `ALTER ROLE ... SET name = value`** ([#108722](https://github.com/ClickHouse/ClickHouse/pull/108722)) and **`ALTER TABLE ... MODIFY CONSTRAINT [IF EXISTS]`** ([#108768](https://github.com/ClickHouse/ClickHouse/pull/108768))
- **`AWS_MSK_IAM` for `kafka_sasl_mechanism`** ([#96100](https://github.com/ClickHouse/ClickHouse/pull/96100))
- **`skip_unavailable_shards_mode` setting** ([#79091](https://github.com/ClickHouse/ClickHouse/pull/79091)) and **query parameters usable as setting values** ([#108760](https://github.com/ClickHouse/ClickHouse/pull/108760))
- **Web UI**: query tabs ([#107826](https://github.com/ClickHouse/ClickHouse/pull/107826)), per-column color coding ([#108873](https://github.com/ClickHouse/ClickHouse/pull/108873)), built-in documentation search at `/docs` ([#108345](https://github.com/ClickHouse/ClickHouse/pull/108345))
- **Performance**: primary key index analysis 5–26% faster, `arrayMin`/`arrayMax` ~1.3–1.5× faster, Delta codec decompression 1.5–5× faster, shared null maps for single-argument `Nullable` functions

### 🔍 Additional Resources

- **Changelog**: [ClickHouse 26.7](https://clickhouse.com/docs/whats-new/changelog)
- **Release Presentation**: [ClickHouse 26.7](https://presentations.clickhouse.com/2026-release-26.7/)
- **`EXPLAIN` Reference**: [docs.clickhouse.com/sql-reference/statements/explain](https://clickhouse.com/docs/sql-reference/statements/explain)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)

### 📝 Notes

- All features verified on ClickHouse 26.7.1
- Each script can be executed independently
- Test data is generated within each SQL file
- Cleanup is commented out for inspection
- `EXPLAIN ANALYZE` runs the query it is given; `01-explain-analyze.sql` therefore executes every example against the 2M-row table
- `02-at-time-zone.sql` changes `session_timezone` and resets it to `UTC` at the end of the section


### 📄 License

[MIT](../../../LICENSE) — free to learn from and modify.

---

**Happy Learning! 🚀**

For questions, see the main [clickhouse-hols README](../../../README.md).

---

## 한국어

ClickHouse 26.7 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 2026년 7월 22일 출시된 ClickHouse 26.7에서 검증된 작동 기능에 집중합니다.

### 📋 개요

ClickHouse 26.7은 측정과 표준 구문을 앞세웁니다. `EXPLAIN ANALYZE`는 쿼리를 실제로 실행하고 모든 플랜 노드에 실제 행 수·바이트·시간 비중·병렬도를 붙여 출력합니다. ANSI `AT TIME ZONE` / `AT LOCAL` 후위 연산자가 `toTimeZone`과 함께 제공되고, 집계 쪽에는 그룹을 직렬화하는 `groupFormat`과 튜플을 원소별로 집계하는 `-Tuple` 조합자가 추가됩니다.

### 🎯 주요 기능

1. **`EXPLAIN ANALYZE`** — 쿼리를 실행하고 노드별 실측 카운터 확인
2. **`AT TIME ZONE` / `AT LOCAL`** — 표준 SQL 후위 시간대 연산자
3. **`groupFormat` + `-Tuple` 조합자** — 임의 출력 포맷으로 그룹 직렬화, 튜플 원소별 집계

### 🚀 빠른 시작

```bash
cd local/releases/26.7
./00-setup.sh

./01-explain-analyze.sh
./02-at-time-zone.sh
./03-groupformat-tuple.sh
```

### 📚 기능 상세

#### 1. `EXPLAIN ANALYZE`

`EXPLAIN ANALYZE <쿼리>`는 쿼리를 실행한 뒤 모든 노드에 실측 카운터를 붙여 플랜을 출력합니다: 선택도가 포함된 입력→출력 행 수, 바이트, 시간 비중, 병렬도, build/probe 시간이 분리된 조인 알고리즘, 인덱스·granule 프루닝 정보입니다. 요약 헤더는 전체 시간을 계획(planning)과 실행(execution)으로 나누고 읽은 행 수와 최대 메모리를 보고합니다. ([#106586](https://github.com/ClickHouse/ClickHouse/pull/106586), [#110668](https://github.com/ClickHouse/ClickHouse/pull/110668))

**테스트 내용:**
- 200만 행 팩트 테이블과 소형 디멘션 테이블
- 같은 쿼리에 대한 `EXPLAIN`(추정 플랜)과 `EXPLAIN ANALYZE`(실측) 비교
- 요약 헤더 읽기: 계획 vs 실행 시간, 읽은 행 수, 최대 메모리
- 플랜 하단부터 위로 선택도(`rows N → M (P%)`) 따라가기
- 주 키 프루닝: `Granules: 1/245`와 `Search Algorithm: binary search`
- 동일한 결과를 비(非)키 컬럼으로 필터링 — 8.19천 행 읽기 vs 200만 행
- 조인 내부: 알고리즘 이름, build된 쪽, build vs probe 시간
- 고카디널리티 `GROUP BY`에서 비용이 집계 단계로 이동하는 모습
- 하나의 질문에 대한 두 가지 작성법 비교 (선(先)필터 vs 후(後)필터)

**핵심 학습 포인트:**
- `EXPLAIN ANALYZE`는 쿼리를 **실행합니다** — 수치가 실측인 이유이며, 부수 효과가 있는 문장에는 사용하지 마세요
- 헤더의 계획/실행 분리는 실행보다 계획 수립이 비싼 플랜을 식별해 줍니다
- 노드별 `rows N → M (P%)`는 데이터 양이 어디서 줄어드는지 정확히 보여줍니다. 행을 줄이지 못하는 노드가 보통 손봐야 할 곳입니다
- `ReadFromMergeTree`는 파트·granule·탐색 알고리즘을 보고하므로 키 활용 여부가 드러납니다
- 조인 노드는 알고리즘(예: `SpillingHashJoin(HashJoin)`)을 명시하고 build/probe 시간을 분리하므로 잘못된 build 쪽을 즉시 알 수 있습니다
- 시간 백분율은 실행 시간 기준이며, `parallelism`은 노드가 실제로 사용한 스레드 수를 보여줍니다

#### 2. `AT TIME ZONE` / `AT LOCAL`

표준 SQL 후위 연산자 `<datetime> AT TIME ZONE '<tz>'`와 `<datetime> AT LOCAL`입니다. 전자는 지정한 시간대로 값을 재표기하고, 후자는 세션의 `session_timezone`을 사용합니다. 둘 다 `toTimeZone()`과 동등하며 `DateTime64` 정밀도를 유지합니다. ([#106092](https://github.com/ClickHouse/ClickHouse/pull/106092))

**테스트 내용:**
- 하나의 UTC 시각을 서울·파리·뉴욕으로 표현
- 타입과 epoch 확인: 타입은 `DateTime('Asia/Seoul')`로 바뀌지만 Unix 타임스탬프는 그대로
- `toTimeZone()` 함수 형태와의 동일성 확인
- 서로 다른 두 `session_timezone` 하에서의 `AT LOCAL`
- 연쇄 변환 — 마지막 연산자가 결과를 결정
- 변환 후에도 마이크로초가 유지되는 `DateTime64(6)`
- 배포 로그를 3개 오피스 시간대로 동시 표현
- 전형적인 리포트 버그: UTC 23:30 이벤트는 서울에서 다음 날짜에 속함
- 필터링 의미 — 비교는 시각(instant) 기준이므로 로컬 날짜 필터는 경계값도 변환해야 함

**핵심 학습 포인트:**
- 이 연산자는 시각이 아니라 시간대 *라벨*을 바꿉니다: 전후로 `toUnixTimestamp()`가 동일합니다
- `toTypeName()`에 변환이 반영됩니다 (`DateTime('UTC')` → `DateTime('Asia/Seoul')`)
- `AT LOCAL`은 `session_timezone`을 따르므로 같은 쿼리가 세션마다 다른 결과를 냅니다
- 초 미만 정밀도가 유지됩니다: `DateTime64(6, 'UTC')` → `DateTime64(6, 'Asia/Seoul')`
- 원본 UTC 값으로 그룹화하면 늦은 저녁 이벤트가 잘못된 로컬 날짜에 집계됩니다 — `toDate()` 전에 변환하세요
- 비교는 시각 기준으로 동작하므로 `WHERE ts AT TIME ZONE 'Asia/Seoul' >= '...'`는 변환하지 않은 형태와 동일하게 필터링됩니다. 로컬 달력 기준 필터에는 *경계값*을 변환하세요

#### 3. `groupFormat` + `-Tuple` 조합자

- `groupFormat('<포맷>')(컬럼...)` — 각 그룹의 행들을 임의의 ClickHouse 출력 포맷으로 직렬화해 하나의 값으로 반환하는 집계 함수 ([#93201](https://github.com/ClickHouse/ClickHouse/pull/93201))
- `-Tuple` 조합자 — 집계를 `Tuple` 인자에 원소별로 적용, 예: `sumTuple((a, b))` ([#98190](https://github.com/ClickHouse/ClickHouse/pull/98190))

**테스트 내용:**
- `groupFormat('CSV')` 기본
- 같은 그룹을 `TSV`, `JSONEachRow`, `Values`로 출력
- `GROUP BY`와 함께 그룹별 페이로드 — 디바이스별 CSV 익스포트
- 방(room)별 `JSONEachRow` 페이로드, 그리고 실제 JSON 키를 얻는 명명 튜플 기법
- `sumTuple` / `avgTuple` / `minTuple` / `maxTuple`을 한 번에, 장문 등가식과 나란히 비교
- 멤버 이름으로 계속 접근 가능한 명명 튜플 (`sumTuple(m).temp`)
- 조합자 중첩: `sumTupleIf((a, b), 조건)`
- 두 기능을 결합한 리포트

**핵심 학습 포인트:**
- 포맷 이름은 `groupFormat`의 **파라미터**, 컬럼은 **인자**입니다: `groupFormat('CSV')(c1, c2)`
- 직렬화된 컬럼은 항상 `c1`, `c2`, … 로 표기됩니다 — 별칭이나 `CSVWithNames`로도 바뀌지 않습니다. 실제 키를 페이로드에 넣으려면 인자를 **명명 튜플**로 감싸세요
- `groupFormat`은 `GROUP BY`를 따르므로 한 쿼리로 다수의 독립 페이로드를 만들 수 있습니다
- `-Tuple`은 N개의 반복 집계를 한 번의 호출로 대체하고 같은 길이의 튜플을 반환합니다
- 명명 튜플의 멤버는 집계 후에도 이름으로 접근할 수 있습니다
- 조합자는 중첩됩니다 — `sumTupleIf`는 튜플 동작과 조건 동작을 함께 적용합니다

### 🆕 26.7의 새로운 기능

- **`EXPLAIN ANALYZE`** — 쿼리 성능 분석 ([#106586](https://github.com/ClickHouse/ClickHouse/pull/106586), [#110668](https://github.com/ClickHouse/ClickHouse/pull/110668))
- **프로젝션 정의의 `WHERE` 절** ([#102347](https://github.com/ClickHouse/ClickHouse/pull/102347))
- **`groupFormat`** 집계 함수 ([#93201](https://github.com/ClickHouse/ClickHouse/pull/93201))
- **`-Tuple` 집계 조합자** ([#98190](https://github.com/ClickHouse/ClickHouse/pull/98190))
- **`AT TIME ZONE` / `AT LOCAL`** 후위 연산자 ([#106092](https://github.com/ClickHouse/ClickHouse/pull/106092))
- **`Remote` / `RemoteSecure` 테이블 엔진** ([#106189](https://github.com/ClickHouse/ClickHouse/pull/106189))
- **`QueryRunner` 테이블 엔진** ([#107888](https://github.com/ClickHouse/ClickHouse/pull/107888))
- **엔진 무관 `SYSTEM STOP/START/PAUSE/CANCEL/REFRESH`** ([#107476](https://github.com/ClickHouse/ClickHouse/pull/107476))
- **`mysql` / `postgresql` / `sqlite` 테이블 함수가 사용자 쿼리를 수용** ([#107740](https://github.com/ClickHouse/ClickHouse/pull/107740))
- **음수 `LIMIT`의 `WITH TIES`** ([#100930](https://github.com/ClickHouse/ClickHouse/pull/100930))
- **`GeoJSON` 출력 포맷** ([#108065](https://github.com/ClickHouse/ClickHouse/pull/108065)) — 입력 포맷은 26.6에 추가됨
- **UTM/MGRS 변환** — `geoToUTM`, `UTMToGeo`, `geoToMGRS`, `MGRSToGeo` ([#108939](https://github.com/ClickHouse/ClickHouse/pull/108939))
- **`geometryIntersectCartesian` / `geometryIntersectSpherical`** ([#110062](https://github.com/ClickHouse/ClickHouse/pull/110062))
- **`digits(n, offset[, length])`** ([#109012](https://github.com/ClickHouse/ClickHouse/pull/109012)), **`sqr`** ([#109061](https://github.com/ClickHouse/ClickHouse/pull/109061))
- **`xxHash64Spark`** ([#108436](https://github.com/ClickHouse/ClickHouse/pull/108436))
- **`dotProductTransposed`** ([#108100](https://github.com/ClickHouse/ClickHouse/pull/108100)), **`randomHadamardTransform`** ([#108227](https://github.com/ClickHouse/ClickHouse/pull/108227))
- **`QBit` stride 파라미터** ([#108103](https://github.com/ClickHouse/ClickHouse/pull/108103)), **`Int8` 원소 타입** ([#108105](https://github.com/ClickHouse/ClickHouse/pull/108105))
- **텍스트 인덱스 `postprocessor` 인자** ([#98939](https://github.com/ClickHouse/ClickHouse/pull/98939), [#108606](https://github.com/ClickHouse/ClickHouse/pull/108606)), **`system.stemmers`** ([#100611](https://github.com/ClickHouse/ClickHouse/pull/100611))
- **Naive Bayes를 `NAIVE_BAYES` 딕셔너리 레이아웃으로 구성** — `naiveBayesClassifierWithProb`, `naiveBayesClassifierWithAllProbs`, `naiveBayesNgrams` 추가, 메모리 약 49배 절감·로드 및 분류 약 11배 향상
- **`SYSTEM UNLOAD DICTIONARY` / `DICTIONARIES`** ([#109639](https://github.com/ClickHouse/ClickHouse/pull/109639)), **딕셔너리별 지연 로딩** ([#108314](https://github.com/ClickHouse/ClickHouse/pull/108314)), **`dictGetRoot`** ([#109459](https://github.com/ClickHouse/ClickHouse/pull/109459))
- **`ALTER USER` / `ALTER ROLE ... SET name = value`** ([#108722](https://github.com/ClickHouse/ClickHouse/pull/108722)), **`ALTER TABLE ... MODIFY CONSTRAINT [IF EXISTS]`** ([#108768](https://github.com/ClickHouse/ClickHouse/pull/108768))
- **`kafka_sasl_mechanism`의 `AWS_MSK_IAM`** ([#96100](https://github.com/ClickHouse/ClickHouse/pull/96100))
- **`skip_unavailable_shards_mode` 설정** ([#79091](https://github.com/ClickHouse/ClickHouse/pull/79091)), **쿼리 파라미터를 설정 값으로 사용** ([#108760](https://github.com/ClickHouse/ClickHouse/pull/108760))
- **Web UI**: 쿼리 탭 ([#107826](https://github.com/ClickHouse/ClickHouse/pull/107826)), 컬럼별 색상 코딩 ([#108873](https://github.com/ClickHouse/ClickHouse/pull/108873)), `/docs` 내장 문서 검색 ([#108345](https://github.com/ClickHouse/ClickHouse/pull/108345))
- **성능**: 주 키 인덱스 분석 5–26% 향상, `arrayMin`/`arrayMax` 약 1.3–1.5배 향상, Delta 코덱 압축 해제 1.5–5배 향상, 단일 인자 `Nullable` 함수의 null map 공유

### 🔍 추가 자료

- **Changelog**: [ClickHouse 26.7](https://clickhouse.com/docs/whats-new/changelog)
- **Release Presentation**: [ClickHouse 26.7](https://presentations.clickhouse.com/2026-release-26.7/)
- **`EXPLAIN` 레퍼런스**: [docs.clickhouse.com/sql-reference/statements/explain](https://clickhouse.com/docs/sql-reference/statements/explain)

### 📝 참고사항

- 모든 기능은 ClickHouse 26.7.1에서 검증
- 각 스크립트는 독립적으로 실행 가능
- 테스트 데이터는 각 SQL 파일 안에서 생성
- 정리(cleanup) 구문은 확인을 위해 주석 처리
- `EXPLAIN ANALYZE`는 대상 쿼리를 실제로 실행합니다 — `01-explain-analyze.sql`은 모든 예제를 200만 행 테이블에 대해 실행합니다
- `02-at-time-zone.sql`은 `session_timezone`을 변경한 뒤 해당 섹션 끝에서 `UTC`로 되돌립니다


### 📄 라이선스

[MIT](../../../LICENSE) — 자유롭게 학습하고 수정하세요.

---

**Happy Learning! 🚀**
