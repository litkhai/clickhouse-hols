# ReplacingMergeTree Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on lab for the behaviour that surprises most ReplacingMergeTree users: deduplication is a **merge-time** side effect, not a write-time guarantee. Until parts merge, duplicate rows are visible, and every query that omits `FINAL` reads them.

### 📋 Overview

The lab inserts the same keys across several parts, then measures what queries return with and without `FINAL`, how long merges take to collapse the duplicates, what `OPTIMIZE TABLE FINAL` actually costs, and which `argMax` rewrite avoids `FINAL` altogether. Every step runs as plain SQL against any ClickHouse server.

### 🎯 Key Features

1. **`FINAL` semantics** — the same query with and without it, on the same data
2. **Consistency drift at scale** — 1M rows across overlapping batches
3. **Merge observation** — parts, in-flight merges, merge history, related settings
4. **`OPTIMIZE TABLE FINAL` and the `argMax` alternative** — cost versus correctness
5. **Operational monitoring** — queries to detect duplicate exposure in production

### 🚀 Quick Start

#### Prerequisites

- A running ClickHouse server — the [oss-mac-setup](../../local/oss-mac-setup/) environment works
- `clickhouse-client` on your PATH, or run the files through the web UI

#### Setup and Run

```bash
cd workload/replacingmergetree

clickhouse-client --queries-file 01-setup.sql
clickhouse-client --queries-file 02-basic-operations.sql
clickhouse-client --queries-file 03-large-scale-tests.sql
clickhouse-client --queries-file 04-consistency-checks.sql
clickhouse-client --queries-file 05-merge-monitoring.sql
clickhouse-client --queries-file 06-optimization.sql
clickhouse-client --queries-file 07-monitoring.sql

# optional, drops the test database
clickhouse-client --queries-file 99-cleanup.sql
```

### 📚 Lab Details

#### 1. Setup (01-setup.sql)

Creates the `blog_test` database and two `ReplacingMergeTree(updated_at)` tables ordered by `(user_id, event_type)` — one small table for the semantic tests, one for the large-scale run.

#### 2. Basic Operations (02-basic-operations.sql)

Three inserts of the same keys, each landing in its own part, then the same `SELECT` with and without `FINAL`. This is the smallest possible demonstration that a version column does not deduplicate on insert.

#### 3. Large Scale Tests (03-large-scale-tests.sql)

100,000 initial rows, then overlapping update batches (500k and 1M row inserts), with part counts captured after each batch. Shows how duplicate exposure grows with ingest rate rather than staying constant.

#### 4. Consistency Checks (04-consistency-checks.sql)

Per-key row counts, total row counts, and aggregate results computed both ways. The aggregate comparison is the important one: without `FINAL`, sums and counts are simply wrong, not merely stale.

#### 5. Merge Monitoring (05-merge-monitoring.sql)

`system.parts` with part age, `system.merges` for in-flight work, `system.part_log` for merge history, and the session settings that govern when merges are allowed to start.

#### 6. Optimization (06-optimization.sql)

`OPTIMIZE TABLE FINAL` before/after state on both tables, then the `argMax`-based rewrite that returns the latest version per key without `FINAL` and without waiting for a merge.

#### 7. Monitoring (07-monitoring.sql)

Production-shaped queries: part-state monitoring, a duplicate-exposure check that compares row counts with and without `FINAL`, `query_log`-based performance comparison, and per-table statistics.

### 🔑 Key Learning Points

- `ReplacingMergeTree` collapses duplicates **when parts merge**, on an unspecified schedule — never on insert
- Reads without `FINAL` can return several versions of one key; aggregates over them are wrong, not approximate
- `FINAL` is correct but costs a merge-on-read; `argMax` over the version column is often cheaper for a specific access pattern
- `OPTIMIZE TABLE FINAL` is a manual, whole-table rewrite. It is a maintenance operation, not a query-time fix
- Duplicate exposure scales with insert frequency: more parts arriving means more windows where reads see duplicates
- Comparing `count()` with and without `FINAL` is a cheap production canary for this class of bug

### 📂 File Structure

```
replacingmergetree/
├── README.md                     # This document
├── 01-setup.sql                  # Database + two ReplacingMergeTree tables
├── 02-basic-operations.sql       # FINAL semantics across three parts
├── 03-large-scale-tests.sql      # Overlapping batches up to 1M rows
├── 04-consistency-checks.sql     # Row counts and aggregates, with/without FINAL
├── 05-merge-monitoring.sql       # parts, merges, part_log, merge settings
├── 06-optimization.sql           # OPTIMIZE TABLE FINAL and the argMax rewrite
├── 07-monitoring.sql             # Operational monitoring queries
└── 99-cleanup.sql                # Drop the test tables and database
```

### 🔍 Related Labs

- [workload/dedup-engine](../dedup-engine/) — compares deduplication engines against each other
- [workload/delete-benchmark](../delete-benchmark/) — DELETE mechanisms and their costs
- [workload/mv-vs-rmv](../mv-vs-rmv/) — materialized vs refreshable materialized views

### 📝 Notes

- The scripts assume the `blog_test` database is free to create and drop
- `02` and `03` truncate their tables at the top, so they are safe to re-run
- Merge timing is not deterministic; if duplicates have already collapsed when you reach `04`, re-run `03` and query immediately
- `99-cleanup.sql` is destructive and separate on purpose

---

## 한국어

ReplacingMergeTree에서 가장 많이 오해되는 지점을 직접 확인하는 실습입니다: 중복 제거는 쓰기 시점의 보장이 아니라 **머지 시점**의 부수 효과입니다. 파트가 머지되기 전까지 중복 행은 그대로 보이고, `FINAL`을 생략한 모든 쿼리가 그 중복을 읽습니다.

### 📋 개요

같은 키를 여러 파트에 걸쳐 삽입한 뒤, `FINAL` 유무에 따라 결과가 어떻게 달라지는지, 머지가 중복을 정리하는 데 얼마나 걸리는지, `OPTIMIZE TABLE FINAL`의 실제 비용은 무엇인지, `FINAL` 없이 최신 버전을 얻는 `argMax` 대안은 어떤 모습인지 측정합니다. 모든 단계는 일반 SQL이므로 어떤 ClickHouse 서버에서도 실행됩니다.

### 🎯 주요 기능

1. **`FINAL` 의미론** — 동일 데이터에 대해 `FINAL` 유무 비교
2. **대량 데이터에서의 정합성 이탈** — 겹치는 배치로 100만 행
3. **머지 관찰** — 파트, 진행 중 머지, 머지 히스토리, 관련 설정
4. **`OPTIMIZE TABLE FINAL`과 `argMax` 대안** — 비용 대 정확성
5. **운영 모니터링** — 프로덕션에서 중복 노출을 탐지하는 쿼리

### 🚀 빠른 시작

```bash
cd workload/replacingmergetree

clickhouse-client --queries-file 01-setup.sql
clickhouse-client --queries-file 02-basic-operations.sql
clickhouse-client --queries-file 03-large-scale-tests.sql
clickhouse-client --queries-file 04-consistency-checks.sql
clickhouse-client --queries-file 05-merge-monitoring.sql
clickhouse-client --queries-file 06-optimization.sql
clickhouse-client --queries-file 07-monitoring.sql

# 선택: 테스트 데이터베이스 삭제
clickhouse-client --queries-file 99-cleanup.sql
```

### 📚 실습 상세

1. **01-setup.sql** — `blog_test` 데이터베이스와 `ReplacingMergeTree(updated_at)` 테이블 2개 생성 (`ORDER BY (user_id, event_type)`)
2. **02-basic-operations.sql** — 같은 키를 3번 삽입해 각각 별도 파트를 만든 뒤 `FINAL` 유무 비교. 버전 컬럼이 삽입 시 중복을 제거하지 않음을 최소 예제로 확인
3. **03-large-scale-tests.sql** — 초기 10만 행 후 겹치는 업데이트 배치(50만·100만 행), 배치별 파트 수 기록. 중복 노출이 적재 속도에 따라 늘어남을 확인
4. **04-consistency-checks.sql** — 키별 행 수, 전체 행 수, 집계 결과를 양쪽으로 비교. 특히 집계는 `FINAL` 없이는 오래된 값이 아니라 **틀린 값**이 나옵니다
5. **05-merge-monitoring.sql** — 파트 경과 시간이 포함된 `system.parts`, 진행 중 머지(`system.merges`), 머지 히스토리(`system.part_log`), 머지 시작 조건 설정
6. **06-optimization.sql** — 두 테이블의 `OPTIMIZE TABLE FINAL` 전후 상태, 그리고 머지를 기다리지 않고 키별 최신 버전을 얻는 `argMax` 재작성
7. **07-monitoring.sql** — 운영용 쿼리: 파트 상태 모니터링, `FINAL` 유무 행 수 비교를 통한 중복 노출 점검, `query_log` 기반 성능 비교, 테이블별 통계

### 🔑 핵심 학습 포인트

- `ReplacingMergeTree`는 **파트가 머지될 때** 중복을 정리하며, 그 시점은 명시되지 않습니다 — 삽입 시점이 아닙니다
- `FINAL` 없는 읽기는 한 키의 여러 버전을 반환할 수 있고, 그 위의 집계는 근사값이 아니라 오답입니다
- `FINAL`은 정확하지만 읽기 시점 머지 비용을 냅니다. 특정 접근 패턴에서는 버전 컬럼에 대한 `argMax`가 더 저렴합니다
- `OPTIMIZE TABLE FINAL`은 전체 테이블을 수동으로 재작성하는 유지보수 작업입니다 — 쿼리 시점의 해결책이 아닙니다
- 중복 노출은 삽입 빈도에 비례합니다: 파트가 자주 생길수록 읽기가 중복을 보는 구간이 늘어납니다
- `FINAL` 유무의 `count()` 비교는 이 부류의 버그를 잡는 값싼 프로덕션 카나리아입니다

### 🔍 관련 실습

- [workload/dedup-engine](../dedup-engine/) — 중복 제거 엔진 간 비교
- [workload/delete-benchmark](../delete-benchmark/) — DELETE 메커니즘과 비용
- [workload/mv-vs-rmv](../mv-vs-rmv/) — MV와 RMV 비교

### 📝 참고사항

- 스크립트는 `blog_test` 데이터베이스를 생성·삭제할 수 있다고 가정합니다
- `02`, `03`은 시작 시 테이블을 TRUNCATE하므로 재실행이 안전합니다
- 머지 시점은 결정적이지 않습니다. `04`에 도달했을 때 이미 중복이 정리됐다면 `03`을 다시 실행하고 곧바로 조회하세요
- `99-cleanup.sql`은 파괴적 작업이므로 의도적으로 분리해 두었습니다

---

**Happy Learning! 🚀**

## License

[MIT](../../LICENSE) — same as the rest of the repository.

## 라이선스

[MIT](../../LICENSE) — 저장소 전체와 동일합니다.
