# Test Design — pg_duckdb vs pg_clickhouse on a pg_lake + Polaris ILM stack

[English](#english) | [한국어](#한국어)

---

## English

Design document v0.1 as implemented. Where this lab had to differ from the
draft (host size, image availability, what the tools actually support), the
difference is marked **▶ as built** and explained.

### 1. Question

Postgres is the OLTP system of record. Old rows are tiered by `pg_lake` into
Iceberg tables registered in an **Apache Polaris** REST catalog. The write path
is fixed (pg_lake); what is compared is the **read path for cold analytics**:

| Path | Engine | How Postgres reaches the lake |
|---|---|---|
| **A** (baseline) | pg_lake native — `pgduck_server` (DuckDB) | Iceberg tables pg_lake owns |
| **B** | `pg_duckdb` in a separate read instance | DuckDB `iceberg` extension, REST `ATTACH` to Polaris |
| **C** | `pg_clickhouse` FDW → ClickHouse | ClickHouse `DataLakeCatalog` (REST) → Polaris |

Three questions:

1. From what data size × query complexity is pg_lake alone not enough?
2. In that region, is B or C better — counting the **main Postgres node's CPU and
   memory**, not only latency?
3. Is the Polaris-in-the-middle setup operable: consistency, freshness, deletes?

Path A is mandatory because pg_lake already ships a vectorised DuckDB engine. The
practical question is "is the extra component worth it over what pg_lake gives
for free", not "which of B and C is faster".

### 2. Fairness rules

- **Same files.** All three paths read the same Iceberg snapshot / Parquet files
  that pg_lake wrote. Load → tier → `VACUUM (ICEBERG)` → freeze, then measure.
  pg_lake's Iceberg autovacuum is off (`pg_lake_iceberg.autovacuum = off`) and
  snapshots are retained for 7 days.
- **Same SQL.** One Postgres-dialect query file per query, always executed
  through Postgres. Each path exposes the same object names (`lineitem`, `orders`,
  `customer`, …) in its own schema; the runner only changes `search_path`.
- **One path at a time.** ▶ *as built:* engines not under test are **stopped**,
  not paused — on an 8 GB Docker VM a paused container still holds its memory.
- **Fixed caps.** `cpus` and `mem_limit` on every container. Path C uses a second
  node by design, so it is also run in an equal-total mode (§6.4).
- **Correct or void.** Every result is hashed (order-independent, numbers
  normalised to 10 significant digits) and compared with path A. A mismatch
  marks the row `hash_match = NO`, and its timing is not used.

### 3. Architecture

```
                  ┌───────────── pg-main (PG 18.6) ─────────────┐
 datagen ──► MinIO│ heap: hot.* (last 6 months + dimensions)     │
 (DuckDB tpch)  ▲ │ pg_lake ──► pgduck_server (DuckDB)   path A │──── Iceberg commit (REST) ──► Polaris ◄── polaris-db
                │ │ pg_clickhouse FDW ─────────────────  path C │                                  ▲  ▲
                │ └──────────────────────────┬──────────────────┘                                  │  │
                │                            │ native protocol                                     │  │
                │                            ▼                                                     │  │
                ├──────────────── ClickHouse 26.9  DataLakeCatalog(rest) ─────────────────────────┘  │
                │                                                                                     │
                └──────────────── pg-duck (PG 18 + pg_duckdb 1.1)  path B  ATTACH (TYPE iceberg) ─────┘
 runner (Python): drives phases, Docker API for cgroup CPU / memory, MinIO metrics
```

| Instance | Extensions | Role |
|---|---|---|
| pg-main | pg_lake, pg_clickhouse | writes the lake (owns the Iceberg tables), holds hot data, runs paths A and C |
| pg-duck | pg_duckdb | path B only; hot tier + heap dimensions copied in with `pg_dump` after tiering |

pg_lake and pg_duckdb are kept apart because both hook the planner/executor and
`COPY`, and each bundles its own DuckDB build (pg_lake 3.5.3 → DuckDB 1.5.x;
pg_duckdb 1.1.1 → DuckDB 1.4.3, see R6).

### 3.2 Components and versions

| Service | Image / build | Notes |
|---|---|---|
| minio | `bitnamilegacy/minio:2025.7.23` | ▶ *as built:* `minio/minio` and `quay.io/minio/minio` no longer serve public images |
| polaris | `apache/polaris:1.7.0` | persistence `relational-jdbc` on polaris-db; bootstrapped with `polaris-admin-tool:1.7.0` |
| polaris-db | `postgres:17` | |
| pg-main | **built here**: PostgreSQL 18.6 (release build) + pg_lake **v3.5.3** + pg_clickhouse **v0.10.0** | upstream's Dockerfile builds four PG majors with `--enable-cassert`; unusable for timing |
| pg-duck | `pgduckdb/pgduckdb:18-v1.1.1` | DuckDB v1.4.3 inside; ▶ returns wrong results on `month()`-partitioned tables (see §10 R9), so it runs only Q6 and C1, for correctness only |
| pg-duck-main | `pgduckdb/pgduckdb:18-main` | ▶ *added:* path **B′** — pg_duckdb 1.2.0-dev / DuckDB v1.5.4, which has the fix; the pg_duckdb numbers in RESULTS are this path |
| clickhouse | `clickhouse/clickhouse-server:26.9` | `DataLakeCatalog`, filesystem cache `lake_cache` |
| runner | `python:3.12-slim` + psycopg, docker SDK, duckdb, boto3 | |

### 3.3 Resource profile

| Container | Draft | ▶ as built | Why |
|---|---|---|---|
| pg-main | 4 CPU / 12 GB | 4 CPU / 4 GB (shared_buffers 1 GB, pgduck_server memory_limit 2.5 GB) | Docker VM here has 12 vCPU / 7.7 GB |
| pg-duck | 4 / 12 GB | 4 / 4 GB (duckdb.max_memory 2.5 GB) | same |
| clickhouse | 4 / 12 GB | 4 / 4 GB | same |
| equal-total (C only) | pg-main 2 + CH 2 | pg-main 2 + CH 2 | `docker update --cpus` during the run |

### 4. Data

**TPC-H**, generated by DuckDB's `tpch` extension straight to Parquet in MinIO
(sliced `dbgen(children, step)` so SF10 fits in 2 GB).

| SF | lineitem rows | Draft | ▶ as built |
|---|---|---|---|
| 1 | 6.0 M | smoke | stack bring-up and the Phase 0 gate only |
| 10 | 60 M | main comparison | **the one measured run** (light matrix, §6) |
| 30 | 180 M | expected single-node limit | **not run** — 4 GB engines; would measure the VM, not the engines |
| 100 | 600 M | optional | not run |

**Tiering rule.** Rows with `o_orderdate` / `l_shipdate` ≥ `HOT_CUTOFF`
(1998-02-01) stay in heap, the rest go to Iceberg. ▶ *as built:* each fact table
is tiered on its **own** date column (orders by `o_orderdate`, lineitem by
`l_shipdate`) — that is how a real monthly job would partition it; the ILM views
union both tiers so results are unaffected. The flow is the operational one at
every SF: full heap load → monthly `ilm.tier_month()` job → rows deleted from
heap in the same transaction.

**Iceberg layout (fixed).** `lineitem_cold` partitioned `month(l_shipdate)`,
`orders_cold` partitioned `month(o_orderdate)`, dimensions unpartitioned.
`VACUUM (ICEBERG)` after tiering; file counts and sizes before and after are in
`results/sf<N>/layout.csv`.

**Dimension placement (joins only).**

| Scenario | Facts | Dimensions |
|---|---|---|
| D1 all-lake | Iceberg | Iceberg snapshot copy (heap copy also kept) |
| D2 mixed | Iceberg | PG heap only — a cross-source join |

### 5. Path wiring

All paths expose `lineitem`, `orders` (cold tier only), `lineitem_all`,
`orders_all` (hot `UNION ALL` cold) and the six dimensions.

- **A** — `a_d1` / `a_d2` views over `tpch.*` Iceberg tables (`catalog = 'rest'`)
  and `hot.*`. Pushdown: `Custom Scan (Query Pushdown)` = full; a pg_lake
  `Foreign Scan` under Postgres operators = partial.
- **B** — `b_d1` / `b_d2`. The first-choice method worked: DuckDB REST
  `ATTACH 'ilm' AS polaris (TYPE iceberg, …, ACCESS_DELEGATION_MODE 'none')`.
  **R4 confirmed**: the attach lives in the backend's DuckDB instance and is gone
  on the next connection. ▶ *as built:* a PG18 **login event trigger** re-attaches
  on every connection, so any client can use the typed views
  (`r['col']::type … FROM duckdb.query('SELECT * FROM polaris.tpch.…')`).
  Pushdown: `Custom Scan (DuckDBScan)` at the top of the plan = full.
- **C** — ClickHouse `DataLakeCatalog('http://polaris:8181/api/catalog', <s3 key>, <s3 secret>)`
  with `catalog_type = 'rest'`, `vended_credentials = false`; `bench.*` views
  re-expose `polaris.\`tpch.x\`` (R5), pg-main imports them with
  `IMPORT FOREIGN SCHEMA`. Pushdown: aggregation/join in the `Remote SQL` = full.
- Not run: variant C-P (partitionwise aggregate), reference C′ (MergeTree copy).

§5.4 direct baseline: Q6 and Q3 straight on `pgduck_server` (its Unix socket,
`iceberg_scan(metadata.json)`) and on ClickHouse over HTTP.

### 6. Workload

| Tier | Queries | What it probes |
|---|---|---|
| L1 scan/aggregate | Q1, Q6, C1 (monthly count over a quarter — pruning) | scan throughput, partition pruning |
| L2 high-cardinality | C2 (top 100 customers), C3 (distinct parts per month) | hash aggregation memory |
| L3 joins | Q3, Q5, Q9, Q10 | join pushdown, D1 vs D2 |
| L4 complex | Q17, Q18, Q20, Q21, C4 (rank within month) | subqueries, EXISTS, windows |
| L5 ILM | C5 (last 12 months, crosses the cutoff), C6 (point lookup by key), C7 (Q1 on the ILM view) | hot+cold plans, small reads |

TPC-H validation parameters; date arithmetic folded into literals so no path is
penalised for interval handling. D2 is run for every query that touches a
dimension. Matrix: 1 cold + `WARM_ITERS` (5) warm per cell, timeout
`QUERY_TIMEOUT_S` (▶ 300 s instead of 600 s). A cold run restarts the path's
containers after clearing pgduck's `--cache_dir` / ClickHouse's filesystem,
Iceberg-metadata and Parquet-metadata caches, then drops the Docker VM page cache
from a privileged helper.

▶ *as run (light):* the full matrix above is what `03-bench.sh` does, but the
run behind RESULTS is `run-all.sh`: SF10, **9 queries** (Q1, Q6, C1 · C2 · Q3,
Q5 · Q18 · C5, C6), **D1 only, warm only** (1 warm-up + 3 timed runs, median),
paths A (correctness reference), B′ and C; B only on Q6 and C1. Cold months are
written by `setup.py --bulk` in one commit per table instead of the monthly
tiering job. No cold runs, no D2 sweep, no concurrency, faults or ILM-ops phases — the
question was narrowed to “can pg_clickhouse read the Iceberg files, and how does
it compare with pg_duckdb”. Those scripts are kept but were not executed.

**Concurrency (§6.3).** Q6 and Q3, 1/4/8/16 closed-loop clients, ▶ 60 s windows
(draft: 5 min), SF10 only. ▶ *not run.*

### 7. Measurements

| Metric | How |
|---|---|
| latency | client wall-clock incl. full fetch |
| pushdown | `EXPLAIN (VERBOSE)` classified full / partial / none; plans saved |
| pg-main CPU | cgroup `cpu_usage.total_usage` delta — exact core-seconds, not sampled |
| pg-main split | `pgduck_server` utime+stime from `/proc` → DuckDB vs Postgres share on path A |
| engine CPU / memory | same counters on the path's engine container; peak working set sampled at 2 Hz |
| object storage | MinIO `minio_s3_traffic_sent_bytes` / `minio_s3_requests_total` deltas |
| correctness | result hash vs path A |
| tiering | rows/s and seconds per monthly commit |
| freshness | commit → visible in B (new and pooled session) and C |

Result schema (`results/sf<N>/bench.csv`): the draft's columns plus
`pg_main_pgduck_cpu_s` and `error`.

### 8. Phases

| Phase | Script | ▶ as built |
|---|---|---|
| 0 gate | `01-load.sh` → `runner/verify.py` | 0-1…0-5 automated; 0-6 (co-location) not run |
| 1 load + tier + faults | `01-load.sh`, `02-faults.sh` | SF10 bulk load (`--bulk`); **monthly tiering and faults not run** — the SF10 tiering job was started and stopped after orders (73 months, 13.9 M rows, 589 s) and ~49 of 73 lineitem months |
| 2 single query | `03-bench.sh` | SF10, light matrix (§6) |
| 3 concurrency | `04-concurrency.sh` | **not run** |
| 4 ILM ops | `06-ilm-ops.sh` | **not run** (deletes 0.1/1/5 %, freshness, snapshot expiry are scripted) |

Fault injection (scripted, not run) kills pg-main (SIGKILL) at 10–105 % of a calibrated tiering
transaction, and stops Polaris mid-transaction, then classifies where the month's
rows are (rolled back / committed / duplicate / lost / diverged between pg_lake
and ClickHouse-through-Polaris) before re-running the job.

### 10. Risks — outcome

| ID | Risk | Outcome here |
|---|---|---|
| R1 | pg_lake REST catalog not in a release | **cleared** — v3.5.3 has `catalog = 'rest'` + `pg_lake_iceberg.rest_catalog_*` GUCs; no prebuilt image, so built from source |
| R2 | heap↔Iceberg atomicity with an external catalog | **not measured** — `02-faults.sh` exists but was not run |
| R3 | Polaris ↔ MinIO credential vending | static keys everywhere (`stsUnavailable: true`); ClickHouse needs `vended_credentials = false` or Polaris rejects the load |
| R4 | pg_duckdb REST attach per session | **confirmed**; solved with a login event trigger |
| R5 | `ns.table` names vs FDW | ClickHouse views, as planned |
| R6 | DuckDB version skew A vs B | 1.5.x vs 1.4.3 (B) / 1.5.4 (B′); recorded in every row |
| R7 | Docker Desktop VM noise | macOS host; medians of 3 warm runs; no cold runs |
| R8 | disk / memory at SF100 | SF30/100 not run |
| R9 | *(new)* readers disagree on pg_lake's Iceberg | **two interop bugs.** pg_lake writes manifests without the spec-required key-value metadata, so ClickHouse rejects them — [pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659), path C runs on a patched pg_lake (`images/pg-main/patches/`). pg_duckdb 1.1.1's iceberg extension computes `month()` as days/30 and prunes live files — [duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699), release ask [pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083); hence B′ |
| R10 | *(new)* PG18 worker pool | `out of background worker slots` during tiering at SF10: io workers, parallel workers and pg_lake's attached workers share `max_worker_processes` (8) → raised to 16 |

Polaris also needed `ALLOW_UNSTRUCTURED_TABLE_LOCATION`,
`ALLOW_EXTERNAL_TABLE_LOCATION` and `ALLOW_NAMESPACE_CUSTOM_LOCATION` for
client-chosen locations, which pg_lake (and DuckDB) use.

---

## 한국어

설계서 v0.1을 실제로 구현한 내용입니다. 호스트 사양, 이미지 배포 여부, 도구가
실제로 지원하는 범위 때문에 초안과 달라진 부분은 **▶ 실제 구성**으로 표시하고 이유를 적었습니다.

### 1. 질문

Postgres가 OLTP 원장이고, 오래된 행은 `pg_lake`가 **Apache Polaris** REST 카탈로그에
등록된 Iceberg 테이블로 내립니다. 쓰기 경로는 pg_lake로 고정하고, 비교 대상은
**콜드 데이터 분석의 읽기 경로**입니다.

| 경로 | 엔진 | Postgres가 레이크에 닿는 방식 |
|---|---|---|
| **A** (기준선) | pg_lake 내장 — `pgduck_server`(DuckDB) | pg_lake가 소유한 Iceberg 테이블 |
| **B** | 별도 읽기 인스턴스의 `pg_duckdb` | DuckDB `iceberg` 확장, Polaris REST `ATTACH` |
| **C** | `pg_clickhouse` FDW → ClickHouse | ClickHouse `DataLakeCatalog`(REST) → Polaris |

답해야 할 질문 세 가지:

1. 어느 용량 × 복잡도부터 pg_lake 단독으로 부족해지는가?
2. 그 구간에서 B와 C 중 무엇이 나은가? 지연시간뿐 아니라 **메인 Postgres 노드의 CPU·메모리**까지 포함한다.
3. Polaris를 사이에 둔 구성이 정합성·신선도·삭제 측면에서 운영 가능한가?

pg_lake에 이미 벡터화 DuckDB 엔진이 들어 있으므로 A는 반드시 포함합니다. 실무 질문은
"B와 C 중 무엇이 빠른가"가 아니라 "pg_lake가 기본으로 주는 것 대비 추가 컴포넌트를 들일 가치가 있는가"입니다.

### 2. 공정성 원칙

- **동일 파일.** 세 경로 모두 pg_lake가 쓴 같은 Iceberg 스냅샷·Parquet 파일을 읽습니다.
  적재 → tiering → `VACUUM (ICEBERG)` → 동결 후 측정합니다. pg_lake의 Iceberg 자동 vacuum은
  끄고(`pg_lake_iceberg.autovacuum = off`) 스냅샷은 7일 보존합니다.
- **동일 SQL.** 쿼리마다 Postgres 문법 파일 하나를 두고 항상 Postgres를 통해 실행합니다.
  경로별 스키마에 같은 이름(`lineitem`, `orders`, `customer` …)을 두고 runner는 `search_path`만 바꿉니다.
- **순차 실행.** ▶ *실제 구성:* 측정 대상이 아닌 엔진은 pause가 아니라 **stop**합니다.
  8 GB Docker VM에서는 pause된 컨테이너도 메모리를 그대로 잡고 있기 때문입니다.
- **리소스 상한 고정.** 모든 컨테이너에 `cpus`·`mem_limit`를 둡니다. C는 설계상 노드가 하나
  더 있으므로 총량 동일 모드(§6.4)로도 돌립니다.
- **정답이 아니면 무효.** 모든 결과를 해시(순서 무관, 숫자는 유효숫자 10자리로 정규화)해 A와
  비교합니다. 불일치하면 `hash_match = NO`로 기록하고 그 수치는 쓰지 않습니다.

### 3. 아키텍처

구성도는 영문 섹션과 같습니다.

| 인스턴스 | 확장 | 역할 |
|---|---|---|
| pg-main | pg_lake, pg_clickhouse | 레이크 쓰기(Iceberg 테이블 소유), hot 데이터 보관, 경로 A·C |
| pg-duck | pg_duckdb | 경로 B 전용. tiering 후 hot 테이블과 heap 디멘션을 `pg_dump`로 복제 |

pg_lake와 pg_duckdb는 둘 다 planner/executor와 `COPY`에 hook을 걸고, 각자 DuckDB를
번들합니다(pg_lake 3.5.3 → DuckDB 1.5.x, pg_duckdb 1.1.1 → DuckDB 1.4.3, R6). 그래서 분리했습니다.

### 3.2 컴포넌트와 버전

| 서비스 | 이미지/빌드 | 비고 |
|---|---|---|
| minio | `bitnamilegacy/minio:2025.7.23` | ▶ *실제 구성:* `minio/minio`, `quay.io/minio/minio`가 더 이상 공개 이미지를 제공하지 않음 |
| polaris | `apache/polaris:1.7.0` | 영속화 `relational-jdbc`(polaris-db), `polaris-admin-tool:1.7.0`로 bootstrap |
| polaris-db | `postgres:17` | |
| pg-main | **직접 빌드**: PostgreSQL 18.6(release) + pg_lake **v3.5.3** + pg_clickhouse **v0.10.0** | 업스트림 Dockerfile은 PG 4개 버전을 `--enable-cassert`로 빌드 → 성능 측정 불가 |
| pg-duck | `pgduckdb/pgduckdb:18-v1.1.1` | 내장 DuckDB v1.4.3. ▶ `month()` 파티션 테이블에서 결과가 틀려(§10 R9) 정합성 확인용으로 Q6·C1만 실행 |
| pg-duck-main | `pgduckdb/pgduckdb:18-main` | ▶ *추가:* 경로 **B′** — 수정이 들어간 pg_duckdb 1.2.0-dev / DuckDB v1.5.4. RESULTS의 pg_duckdb 수치는 이 경로 |
| clickhouse | `clickhouse/clickhouse-server:26.9` | `DataLakeCatalog`, 파일시스템 캐시 `lake_cache` |
| runner | `python:3.12-slim` + psycopg, docker SDK, duckdb, boto3 | |

### 3.3 리소스 프로파일

| 컨테이너 | 초안 | ▶ 실제 구성 | 이유 |
|---|---|---|---|
| pg-main | 4 CPU / 12 GB | 4 CPU / 4 GB (shared_buffers 1 GB, pgduck_server memory_limit 2.5 GB) | 이 호스트의 Docker VM이 12 vCPU / 7.7 GB |
| pg-duck | 4 / 12 GB | 4 / 4 GB (duckdb.max_memory 2.5 GB) | 동일 |
| clickhouse | 4 / 12 GB | 4 / 4 GB | 동일 |
| 총량 동일(C만) | pg-main 2 + CH 2 | pg-main 2 + CH 2 | 실행 중 `docker update --cpus` |

### 4. 데이터

**TPC-H**를 DuckDB `tpch` 확장으로 생성해 MinIO에 Parquet으로 바로 씁니다
(`dbgen(children, step)`으로 쪼개 SF10도 2 GB 안에서 생성).

| SF | lineitem 행 수 | 초안 | ▶ 실제 구성 |
|---|---|---|---|
| 1 | 600만 | 스모크 | 스택 구성과 Phase 0 게이트만 |
| 10 | 6,000만 | 기본 비교 | **실제 측정한 유일한 SF** (경량 매트릭스, §6) |
| 30 | 1.8억 | 단일 노드 한계 예상 구간 | **미실행** — 엔진당 4 GB라 엔진이 아니라 VM을 재게 됨 |
| 100 | 6억 | 선택 | 미실행 |

**티어링 규칙.** `o_orderdate` / `l_shipdate`가 `HOT_CUTOFF`(1998-02-01) 이후인 행은 heap에
남고 나머지는 Iceberg로 갑니다. ▶ *실제 구성:* 팩트 테이블은 **각자의 날짜 컬럼**으로 나눕니다
(orders는 `o_orderdate`, lineitem은 `l_shipdate`). 실제 월 단위 작업이라면 그렇게 나눌 것이고,
ILM 뷰가 두 티어를 합치므로 결과에는 영향이 없습니다. 모든 SF에서 운영과 같은 흐름을 탑니다:
heap 전량 적재 → 월 단위 `ilm.tier_month()` 작업 → 같은 트랜잭션에서 heap 삭제.

**Iceberg 레이아웃(고정).** `lineitem_cold`는 `month(l_shipdate)`, `orders_cold`는
`month(o_orderdate)` 파티션, 디멘션은 파티션 없음. tiering 후 `VACUUM (ICEBERG)`, 전후 파일 수와
크기는 `results/sf<N>/layout.csv`에 있습니다.

**디멘션 배치(조인 쿼리만).**

| 시나리오 | 팩트 | 디멘션 |
|---|---|---|
| D1 All-lake | Iceberg | Iceberg 스냅샷 복제(heap에도 유지) |
| D2 Mixed | Iceberg | PG heap만 — 크로스 소스 조인 |

### 5. 경로별 구성

모든 경로가 `lineitem`, `orders`(콜드만), `lineitem_all`, `orders_all`(hot `UNION ALL` cold)과
디멘션 6개를 같은 이름으로 노출합니다.

- **A** — `tpch.*` Iceberg 테이블(`catalog = 'rest'`)과 `hot.*` 위의 `a_d1` / `a_d2` 뷰.
  pushdown 판정: `Custom Scan (Query Pushdown)`이면 full, Postgres 연산자 아래 pg_lake
  `Foreign Scan`이면 partial.
- **B** — `b_d1` / `b_d2`. 1순위 방식이 동작했습니다: DuckDB REST
  `ATTACH 'ilm' AS polaris (TYPE iceberg, …, ACCESS_DELEGATION_MODE 'none')`.
  **R4 확인**: attach는 백엔드의 DuckDB 인스턴스에만 있어서 다음 연결에서는 사라집니다.
  ▶ *실제 구성:* PG18 **login 이벤트 트리거**가 연결마다 다시 attach하므로, 어떤 클라이언트든
  타입이 붙은 뷰(`r['col']::type … FROM duckdb.query('SELECT * FROM polaris.tpch.…')`)를
  그대로 쓸 수 있습니다. pushdown 판정: 계획 최상단이 `Custom Scan (DuckDBScan)`이면 full.
- **C** — ClickHouse `DataLakeCatalog('http://polaris:8181/api/catalog', <s3 key>, <s3 secret>)`,
  `catalog_type = 'rest'`, `vended_credentials = false`. `bench.*` 뷰로 ``polaris.`tpch.x` ``를
  재노출(R5)하고 pg-main에서 `IMPORT FOREIGN SCHEMA`. pushdown 판정: `Remote SQL`에 집계·조인이 있으면 full.
- 미실행: 변형 C-P(partitionwise aggregate), 참고 경로 C′(MergeTree 적재).

§5.4 직접 실행 베이스라인: Q6, Q3를 `pgduck_server`(Unix 소켓, `iceberg_scan(metadata.json)`)와
ClickHouse HTTP로 직접 실행합니다.

### 6. 워크로드

| Tier | 쿼리 | 보는 것 |
|---|---|---|
| L1 스캔·집계 | Q1, Q6, C1(분기 내 월별 건수 — pruning) | 스캔 처리량, 파티션 pruning |
| L2 고카디널리티 | C2(고객 Top 100), C3(월별 distinct partkey) | 해시 집계 메모리 |
| L3 조인 | Q3, Q5, Q9, Q10 | 조인 pushdown, D1 vs D2 |
| L4 복합 | Q17, Q18, Q20, Q21, C4(월 내 순위) | 서브쿼리, EXISTS, 윈도우 |
| L5 ILM | C5(최근 12개월, 경계 걸침), C6(키 단건 조회), C7(ILM 뷰에 Q1) | hot+cold 계획, 소량 조회 |

TPC-H 검증용 파라미터를 쓰고, 날짜 연산은 리터럴로 미리 계산해 interval 처리 차이로 불리해지는
경로가 없게 했습니다. D2는 디멘션을 참조하는 모든 쿼리에 대해 돌립니다. 셀마다 cold 1회 +
warm `WARM_ITERS`(5)회, 타임아웃 `QUERY_TIMEOUT_S`(▶ 600초 대신 300초). cold run은 pgduck의
`--cache_dir`, ClickHouse의 파일시스템·Iceberg 메타데이터·Parquet 메타데이터 캐시를 비우고
해당 경로 컨테이너를 재시작한 뒤, 권한 있는 헬퍼 컨테이너로 Docker VM의 page cache를 drop합니다.

▶ *실제 실행(경량):* 위 전체 매트릭스는 `03-bench.sh`가 하는 일이고, RESULTS의 근거는
`run-all.sh`입니다. SF10, **쿼리 9개**(Q1, Q6, C1 · C2 · Q3, Q5 · Q18 · C5, C6), **D1만, warm만**
(warm-up 1회 + 측정 3회, 중앙값), 경로 A(정답 기준), B′, C이며 B는 Q6·C1만. 콜드 월은 월 단위
tiering 작업 대신 `setup.py --bulk`로 테이블당 커밋 1번에 기록합니다. cold run, D2 전체,
동시성·장애·ILM 운영 단계는 돌리지 않았습니다 —
질문을 “pg_clickhouse로 Iceberg 파일을 읽을 수 있는가, pg_duckdb와 비교하면 어떤가”로 좁혔기
때문입니다. 해당 스크립트는 남겨 두었지만 실행하지 않았습니다.

**동시성(§6.3).** Q6, Q3에 closed-loop 클라이언트 1/4/8/16, ▶ 구간당 60초(초안 5분), SF10만. ▶ *미실행.*

### 7. 측정 항목

| 지표 | 방법 |
|---|---|
| 지연시간 | 전체 fetch를 포함한 클라이언트 wall-clock |
| pushdown | `EXPLAIN (VERBOSE)`로 full / partial / none 판정, 계획 저장 |
| pg-main CPU | cgroup `cpu_usage.total_usage` 차분 — 샘플링이 아닌 정확한 core-seconds |
| pg-main 내부 분리 | `/proc`에서 `pgduck_server` utime+stime → 경로 A의 DuckDB 몫과 Postgres 몫 분리 |
| 엔진 CPU·메모리 | 경로 엔진 컨테이너의 같은 카운터, peak working set은 2 Hz 샘플링 |
| 오브젝트 스토리지 | MinIO `minio_s3_traffic_sent_bytes` / `minio_s3_requests_total` 차분 |
| 정합성 | 경로 A 대비 결과 해시 |
| tiering | 월 단위 커밋당 행/초와 소요 시간 |
| 신선도 | 커밋 → B(새 세션·유지 세션)와 C에서 보이기까지 |

결과 스키마(`results/sf<N>/bench.csv`)는 초안 컬럼에 `pg_main_pgduck_cpu_s`와 `error`를 더했습니다.

### 8. 단계

| 단계 | 스크립트 | ▶ 실제 구성 |
|---|---|---|
| 0 게이트 | `01-load.sh` → `runner/verify.py` | 0-1…0-5 자동화, 0-6(동일 인스턴스 공존) 미실행 |
| 1 적재·tiering·장애 | `01-load.sh`, `02-faults.sh` | SF10 bulk 적재(`--bulk`). **월 단위 tiering·장애 주입 미실행** — SF10 tiering은 orders(73개월, 1,390만 행, 589초)와 lineitem 73개월 중 약 49개월까지 진행 후 중단 |
| 2 단일 쿼리 | `03-bench.sh` | SF10, 경량 매트릭스(§6) |
| 3 동시성 | `04-concurrency.sh` | **미실행** |
| 4 ILM 운영 | `06-ilm-ops.sh` | **미실행** (삭제 0.1/1/5 %, 신선도, 스냅샷 만료는 스크립트만 있음) |

장애 주입(스크립트만 있고 미실행)은 보정한 tiering 트랜잭션 시간의 10–105 % 시점에 pg-main을 SIGKILL하거나
트랜잭션 도중 Polaris를 중지합니다. 그런 다음 그 달의 행이 어디 있는지(롤백 / 커밋 / 중복 / 유실 /
pg_lake와 Polaris 경유 ClickHouse 간 불일치)를 분류하고 작업을 다시 실행합니다.

### 10. 리스크 결과

| ID | 리스크 | 결과 |
|---|---|---|
| R1 | pg_lake REST 카탈로그가 릴리스에 없음 | **해소** — v3.5.3에 `catalog = 'rest'`와 `pg_lake_iceberg.rest_catalog_*` GUC가 있음. 배포 이미지가 없어 소스 빌드 |
| R2 | 외부 카탈로그 사용 시 heap↔Iceberg 원자성 | **미측정** — `02-faults.sh`는 있으나 실행하지 않음 |
| R3 | Polaris ↔ MinIO credential vending | 전 구간 정적 키(`stsUnavailable: true`). ClickHouse는 `vended_credentials = false`가 없으면 Polaris가 loadTable을 거부 |
| R4 | pg_duckdb REST attach 세션 지속성 | **확인됨**, login 이벤트 트리거로 해결 |
| R5 | `ns.table` 이름과 FDW 호환 | 계획대로 ClickHouse 뷰로 재노출 |
| R6 | A·B DuckDB 버전 차이 | 1.5.x vs 1.4.3(B) / 1.5.4(B′), 모든 결과 행에 기록 |
| R7 | Docker Desktop VM 노이즈 | macOS 호스트. warm 3회 중앙값, cold run 없음 |
| R8 | SF100 디스크·메모리 | SF30/100 미실행 |
| R9 | *(신규)* pg_lake Iceberg를 리더마다 다르게 읽음 | **상호운용 버그 2건.** pg_lake가 스펙 필수 key-value 메타데이터 없이 manifest를 써서 ClickHouse가 거부 — [pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659), 경로 C는 패치한 pg_lake(`images/pg-main/patches/`)로 실행. pg_duckdb 1.1.1의 iceberg 확장은 `month()`를 days/30으로 계산해 살아 있는 파일을 pruning — [duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699), 릴리스 요청 [pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083). 그래서 B′를 추가 |
| R10 | *(신규)* PG18 worker 풀 | SF10 tiering 중 `out of background worker slots`: io worker, 병렬 worker, pg_lake attached worker가 `max_worker_processes`(8)를 공유 → 16으로 상향 |

Polaris는 클라이언트가 위치를 정하는 테이블(pg_lake, DuckDB 모두 해당)을 위해
`ALLOW_UNSTRUCTURED_TABLE_LOCATION`, `ALLOW_EXTERNAL_TABLE_LOCATION`,
`ALLOW_NAMESPACE_CUSTOM_LOCATION`도 켜야 했습니다.
