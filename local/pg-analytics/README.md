# pg_lake ILM Analytics — pg_duckdb vs pg_clickhouse on Iceberg (Polaris)

[English](#english) | [한국어](#한국어)

---

## English

Postgres is the OLTP system; old rows are tiered by **pg_lake** into Iceberg
tables registered in an **Apache Polaris** REST catalog. This lab asks which
**read path** should serve analytics on that cold data, measured on one frozen
Iceberg snapshot that all paths share:

| Path | How Postgres reads the lake | Runs where |
|---|---|---|
| **A** pg_lake native (baseline) | pg_lake's own Iceberg tables → `pgduck_server` (DuckDB) | the main Postgres node |
| **B** pg_duckdb 1.1.1 (+ **B′** main build, reference) | DuckDB `iceberg` extension, REST `ATTACH` to Polaris | a separate Postgres read node |
| **C** pg_clickhouse → ClickHouse 26.9 | `DataLakeCatalog` (REST) → Polaris → the same files | ClickHouse node; Postgres only plans and fetches rows |

Nothing is loaded into ClickHouse tables: path C reads pg_lake's Iceberg
files in place. The full test design, including every place where the lab
differs from the v0.1 draft, is in [docs/DESIGN.md](docs/DESIGN.md). Results
are in [RESULTS.md](RESULTS.md), and a blog-style write-up is in
[blog/pg-lake-duckdb-vs-clickhouse.en.md](blog/pg-lake-duckdb-vs-clickhouse.en.md).

### ⚠️ Two interoperability bugs this lab found

1. **pg_lake 3.5.3 writes Iceberg manifests without the spec-required metadata**
   (`schema`, `partition-spec`, `format-version`, `content`, …). Spec-strict
   readers reject them: ClickHouse fails with `No partition-spec in iceberg
   manifest file`. This is a writer bug, not a pg_clickhouse one — reported
   upstream as [Snowflake-Labs/pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659).
   The lab builds pg_lake with the fix from that issue
   ([images/pg-main/patches/](images/pg-main/patches/)), so **path C numbers are
   "pg_lake + patch"**. Without it, path C cannot read the tables at all.
2. **pg_duckdb 1.1.1 (DuckDB 1.4.3 `iceberg` extension) returns wrong results**
   on range filters over `month()`-partitioned tables: it prunes files it must
   read (`l_shipdate >= '1994-01-01'` drops January–April 1994). Standalone
   DuckDB 1.4.5 / 1.5.5 and the pg_duckdb main build (1.2.0, DuckDB 1.5.4) are
   correct, which is why B′ is measured as a reference. Cells where B's result
   hash differs from A's are reported as **wrong** and never timed. This is the
   known month-transform bug [duckdb/duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699)
   (`days / 30` instead of calendar months), fixed upstream but not yet in a
   pg_duckdb release — raised as [duckdb/pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083).

The first SF10 run, on pg_clickhouse 0.3.2, crashed a backend (SIGSEGV) on C6.
That bug, two foreign scans sharing one binary-driver connection, is already
fixed in v0.10.0, which the lab now builds; see [RESULTS.md](RESULTS.md) §4.

### 🧱 Architecture

```
 datagen (DuckDB tpch) ─► MinIO s3://warehouse/staging ─┐
                                                         ▼
 ┌──────── pg-main: PostgreSQL 18.6 ────────────────────────────────┐  Iceberg commit (REST)
 │ hot.*  heap: last 6 months + dimensions                          │ ─────────────► Polaris 1.7.0 ◄─ polaris-db
 │ tpch.* Iceberg (catalog='rest') ── pg_lake ─► pgduck_server  (A) │                  ▲    ▲
 │ ch.*   foreign tables ─ pg_clickhouse ────────────────────┐  (C) │                  │    │
 └───────────────────────────────────────────────────────────┼──────┘                  │    │
                           ClickHouse 26.9  DataLakeCatalog ◄─┘ ────────────────────────┘    │
 pg-duck      (PG 18 + pg_duckdb 1.1.1, DuckDB 1.4.3)  ATTACH TYPE iceberg  (B) ────────────┤
 pg-duck-main (PG 18 + pg_duckdb 1.2.0, DuckDB 1.5.4)  ATTACH TYPE iceberg  (B′) ───────────┘
 runner: phases, Docker API (cgroup CPU, memory), MinIO v3 metrics
```

- **Same files, same SQL.** One Postgres-dialect file per query; each path
  exposes `lineitem`, `orders` (cold tier), `lineitem_all`, `orders_all`
  (hot `UNION ALL` cold) and six dimensions in its own schema, and the runner
  only switches `search_path`.
- **Credentials.** pg_lake commits as the Polaris principal `ilm_writer`;
  B/B′/C read as `ilm_reader`, which has read-only privileges. MinIO has no STS, so
  every engine uses static S3 keys (`vended_credentials = false` on the
  ClickHouse side).

### 📁 Layout

```
pg-analytics/
├── 00-setup.sh … 07-report.sh, 99-cleanup.sh   numbered entry points
├── run-all.sh                  the light run behind RESULTS.md (SF10, ~20 min), unattended
├── compose.yaml, .env.example  services and resource caps
├── images/pg-main/             PG 18 + pg_lake 3.5.3 (+ patch) + pg_clickhouse 0.10.0, release build
├── images/runner/              Python driver image (psql 18, docker SDK, duckdb)
├── init/polaris/bootstrap.py   catalog, principals, grants
├── init/pg-main/*.sql          extensions + REST GUCs, heap load, Iceberg tables, FDW, views
├── init/clickhouse/            DataLakeCatalog + bench views, filesystem cache
├── datagen/gen.py              DuckDB tpch → Parquet in MinIO (sliced, resumable)
├── ilm/tiering.sql             idempotent monthly heap → Iceberg move
├── queries/tpch, queries/custom  10 TPC-H + 7 custom queries (L1–L5)
├── runner/                     setup, verify (Phase 0), bench, faults, concurrency, direct, ilm_ops
├── analysis/report.py          SUMMARY.md tables + charts
├── docs/DESIGN.md              test design (bilingual)
├── RESULTS.md                  findings (bilingual)
├── blog/                       the write-up as a blog post, .en.md and .ko.md
└── results/                    raw CSVs, plans, charts per scale factor
```

### 🚀 Quick start

Needs Docker with ≥ 8 GB for the VM, ~40 GB free disk, and time: the first
`00-setup.sh` compiles PostgreSQL, pg_lake (with DuckDB) and pg_clickhouse
(30–60 min).

The light run that produced [RESULTS.md](RESULTS.md): SF10, with the cold
months written straight into Iceberg (`setup.py --bulk`, no monthly tiering
job). It runs 9 queries covering L1–L5 with dimensions in the lake (D1), with
1 warm-up + 5 timed runs on A/B′/C. B runs only Q6 and C1, to show its pruning
bug. It takes about 20 min after the build:

```bash
cd local/pg-analytics
./00-setup.sh          # build, start, bootstrap Polaris, stage TPC-H for SF_LIST
./run-all.sh 10        # bulk load, Phase 0 gate, bench A/B'/C (+ B on Q6, C1)
./07-report.sh         # results/SUMMARY.md + results/charts/
```

The other numbered scripts run the full design step by step: `01-load.sh`
(monthly tiering), `03-bench.sh` (all 17 queries, cold runs, D2) and the rest.
They are kept, but were **not** run end to end for RESULTS.md.

| Script | Phase | What it does |
|---|---|---|
| `01-load.sh <sf>` | 1 + 0 | heap load, monthly `ilm.tier_month()` into Iceberg, VACUUM, readers, integration gate |
| `02-faults.sh <sf>` | 1 | SIGKILL pg-main / stop Polaris during tiering commits, classify, re-run |
| `03-bench.sh <sf>` | 2 | cold + 5 warm per query × path × dimension placement, EXPLAIN, result hashes |
| `04-concurrency.sh <sf>` | 3 | 1/4/8/16 closed-loop clients on Q6 and Q3 |
| `05-direct.sh <sf>` | §5.4 | Q6/Q3 straight on pgduck_server and ClickHouse (cost of going through Postgres) |
| `06-ilm-ops.sh <sf>` | 4 | erasure deletes, freshness lag, snapshot expiry (modifies data: run last) |
| `99-cleanup.sh` | | stop everything, delete volumes |

Interactive shells: `psql -h localhost -p 15432 -U postgres ilm` (pg-main),
`-p 15433` (pg-duck), `-p 15434` (pg-duck-main),
`docker exec -it pga-clickhouse clickhouse-client`.

### 🔍 Things worth knowing

- **pg_lake + REST catalog:** database name = Polaris catalog (warehouse), schema
  = namespace. `catalog = 'rest'` tables keep no `metadata_location` locally
  (`iceberg_tables` is empty for them); ask Polaris. File inventory is in
  `lake_table.files`.
- **Polaris** must allow client-chosen locations
  (`ALLOW_UNSTRUCTURED_TABLE_LOCATION`, `ALLOW_EXTERNAL_TABLE_LOCATION`,
  `ALLOW_NAMESPACE_CUSTOM_LOCATION`), or pg_lake's and DuckDB's creates fail.
- **pg_duckdb's `ATTACH` is per session.** A PG18 login event trigger
  re-attaches Polaris for every connection. It must not use an `EXCEPTION`
  block, because DuckDB rejects the subtransaction it opens.
- **ClickHouse config.d is replaced by the mount** here, so `listen_host` is
  restated in `init/clickhouse/config.d/lake.xml`.
- **MinIO's v2 cluster metrics lag ~10 s.** The runner uses the v3 API
  metrics, or reads land on the next query's row.
- **MinIO images:** `minio/minio` no longer publishes to Docker Hub; the lab
  pins `bitnamilegacy/minio`.
- **`max_worker_processes = 16`.** PG18 io workers, parallel workers and
  pg_lake's per-statement workers share the default pool of 8. SF10 tiering
  failed with `out of background worker slots` until it was raised.
- **Bulk writes go one year per commit.** A single 54 M-row partitioned
  `INSERT` into `lineitem_cold` got pg-main OOM-killed at the 4 GB cap.
- **dbgen slices every table, nation and region included.** With
  `children > 1` each slice holds only part of them, so `datagen/gen.py`
  writes those two from their own run.

### 📝 License

[MIT](../../LICENSE). The pg_lake patch under `images/pg-main/patches/` is a
change to pg_lake (Apache-2.0) and is offered upstream under that licence.

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2026-09-25

---

## 한국어

Postgres가 OLTP 원장이고, 오래된 행은 **pg_lake**가 **Apache Polaris** REST 카탈로그에
등록된 Iceberg 테이블로 내립니다. 이 실습은 콜드 데이터 분석을 어떤 **읽기 경로**로
처리해야 하는지를, 모든 경로가 공유하는 동결된 Iceberg 스냅샷 하나로 측정합니다.

| 경로 | Postgres가 레이크를 읽는 방식 | 실행 위치 |
|---|---|---|
| **A** pg_lake 내장(기준선) | pg_lake 자체 Iceberg 테이블 → `pgduck_server`(DuckDB) | 메인 Postgres 노드 |
| **B** pg_duckdb 1.1.1 (+ 참고용 **B′** main 빌드) | DuckDB `iceberg` 확장, Polaris REST `ATTACH` | 별도 Postgres 읽기 노드 |
| **C** pg_clickhouse → ClickHouse 26.9 | `DataLakeCatalog`(REST) → Polaris → 같은 파일 | ClickHouse 노드. Postgres는 계획과 결과 수신만 |

ClickHouse 테이블에는 아무것도 적재하지 않습니다. 경로 C는 pg_lake가 쓴 Iceberg 파일을
그 자리에서 읽습니다. 초안 v0.1과 달라진 부분을 포함한 전체 설계는
[docs/DESIGN.md](docs/DESIGN.md)에, 결과는 [RESULTS.md](RESULTS.md)에 있습니다. 블로그 형식 글은
[blog/pg-lake-duckdb-vs-clickhouse.ko.md](blog/pg-lake-duckdb-vs-clickhouse.ko.md)에 있습니다.

### ⚠️ 이 실습에서 발견한 상호운용성 버그 두 가지

1. **pg_lake 3.5.3은 스펙 필수 메타데이터(`schema`, `partition-spec`, `format-version`,
   `content` 등) 없이 Iceberg manifest를 씁니다.** 스펙을 엄격히 지키는 리더는 이를 거부하고,
   ClickHouse는 `No partition-spec in iceberg manifest file`로 실패합니다. pg_clickhouse가 아니라
   작성자 쪽 버그이며, [Snowflake-Labs/pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659)로
   보고했습니다. 이 실습은 그 이슈의 수정을 적용해 pg_lake를 빌드하므로
   ([images/pg-main/patches/](images/pg-main/patches/)) **경로 C 수치는 "pg_lake + 패치" 기준**입니다.
   패치가 없으면 경로 C는 테이블을 아예 읽지 못합니다.
2. **pg_duckdb 1.1.1(DuckDB 1.4.3 `iceberg` 확장)은 `month()` 파티션 테이블에 범위 필터를
   걸면 틀린 결과를 냅니다.** 읽어야 할 파일을 pruning으로 걸러내서, `l_shipdate >= '1994-01-01'`이면
   1994년 1~4월이 빠집니다. standalone DuckDB 1.4.5 / 1.5.5와 pg_duckdb main 빌드(1.2.0, DuckDB 1.5.4)는
   정확하므로 B′를 참고치로 측정합니다. 결과 해시가 A와 다른 B 셀은 **wrong**으로 표시하고 시간은 쓰지 않습니다.
   이미 알려진 month 변환 버그 [duckdb/duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699)
   (달력 월 대신 `days / 30`으로 계산)입니다. 업스트림에서는 고쳐졌지만 pg_duckdb 릴리스에는 아직 반영되지 않아
   [duckdb/pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083)으로 알렸습니다.

첫 SF10 실행은 pg_clickhouse 0.3.2였고, C6에서 backend가 SIGSEGV로 죽었습니다. foreign scan
두 개가 binary driver 연결 하나를 같이 쓰던 버그로, v0.10.0에서 이미 고쳐졌습니다. 실습은 이제
v0.10.0을 빌드합니다. [RESULTS.md](RESULTS.md) §4 참고.

### 🧱 아키텍처

구성도는 영문 섹션과 같습니다.

- **동일 파일, 동일 SQL.** 쿼리마다 Postgres 문법 파일 하나를 씁니다. 각 경로는 자기 스키마에
  `lineitem`, `orders`(콜드), `lineitem_all`, `orders_all`(hot `UNION ALL` cold)과 디멘션 6개를
  같은 이름으로 두고, runner는 `search_path`만 바꿉니다.
- **자격증명.** pg_lake는 Polaris principal `ilm_writer`로 커밋하고, B/B′/C는 읽기 전용 권한만 있는
  `ilm_reader`로 읽습니다. MinIO에 STS가 없으므로 모든 엔진이 정적 S3 키를 씁니다(ClickHouse는
  `vended_credentials = false`).

### 📁 구성

디렉터리 구성은 영문 섹션과 같습니다.

### 🚀 빠른 시작

Docker VM 메모리 8 GB 이상, 디스크 여유 약 40 GB가 필요합니다. 처음 `00-setup.sh`를 돌리면
PostgreSQL, pg_lake(DuckDB 포함), pg_clickhouse를 컴파일하므로 30~60분 걸립니다.

[RESULTS.md](RESULTS.md)를 만든 경량 실행입니다. SF10이고, cold 월은 월 단위 tiering 작업 없이
Iceberg에 바로 기록합니다(`setup.py --bulk`). L1–L5를 대표하는 쿼리 9개를 디멘션을 레이크에 둔
상태(D1)로 돌리며, A/B′/C는 warm-up 1회 + 측정 5회입니다. B는 pruning 버그를 보여주려고 Q6·C1만
돌립니다. 빌드 후 약 20분 걸립니다.

```bash
cd local/pg-analytics
./00-setup.sh          # 빌드, 기동, Polaris bootstrap, SF_LIST의 TPC-H 생성
./run-all.sh 10        # bulk 적재, Phase 0 게이트, A/B'/C 벤치(+ B는 Q6, C1)
./07-report.sh         # results/SUMMARY.md + results/charts/
```

나머지 번호 스크립트는 전체 설계를 단계별로 수행합니다. `01-load.sh`(월 단위 tiering),
`03-bench.sh`(17개 쿼리 전체, cold run, D2) 등입니다. 남겨 두었지만 RESULTS.md를 위해
끝까지 실행하지는 **않았습니다**.

| 스크립트 | 단계 | 내용 |
|---|---|---|
| `01-load.sh <sf>` | 1 + 0 | heap 적재, 월 단위 `ilm.tier_month()`로 Iceberg 이관, VACUUM, 리더 연결, 연동 게이트 |
| `02-faults.sh <sf>` | 1 | tiering 커밋 중 pg-main SIGKILL / Polaris 중지, 상태 분류 후 재실행 |
| `03-bench.sh <sf>` | 2 | 쿼리 × 경로 × 디멘션 배치마다 cold 1회 + warm 5회, EXPLAIN, 결과 해시 |
| `04-concurrency.sh <sf>` | 3 | Q6, Q3에 closed-loop 클라이언트 1/4/8/16 |
| `05-direct.sh <sf>` | §5.4 | Q6/Q3를 pgduck_server와 ClickHouse에 직접 실행(Postgres 경유 비용) |
| `06-ilm-ops.sh <sf>` | 4 | 파기 삭제, 신선도 지연, 스냅샷 만료(데이터를 바꾸므로 마지막에 실행) |
| `99-cleanup.sh` | | 전체 중지, 볼륨 삭제 |

접속: `psql -h localhost -p 15432 -U postgres ilm`(pg-main), `-p 15433`(pg-duck),
`-p 15434`(pg-duck-main), `docker exec -it pga-clickhouse clickhouse-client`.

### 🔍 알아둘 점

- **pg_lake + REST 카탈로그:** 데이터베이스 이름 = Polaris 카탈로그(warehouse), 스키마 = 네임스페이스.
  `catalog = 'rest'` 테이블은 `metadata_location`을 로컬에 두지 않아 `iceberg_tables`가 비어 있고,
  Polaris에 물어봐야 합니다. 파일 목록은 `lake_table.files`에 있습니다.
- **Polaris**는 클라이언트가 정하는 위치를 허용해야 합니다(`ALLOW_UNSTRUCTURED_TABLE_LOCATION`,
  `ALLOW_EXTERNAL_TABLE_LOCATION`, `ALLOW_NAMESPACE_CUSTOM_LOCATION`). 그렇지 않으면 pg_lake와 DuckDB의
  테이블 생성이 실패합니다.
- **pg_duckdb의 `ATTACH`는 세션 단위**입니다. PG18 login 이벤트 트리거가 연결마다 Polaris를 다시
  attach합니다. 트리거에 `EXCEPTION` 블록을 쓰면 안 됩니다. 서브트랜잭션이 열리는데 DuckDB가 이를 거부합니다.
- **ClickHouse config.d가 마운트로 교체**되므로 `listen_host`를 `init/clickhouse/config.d/lake.xml`에
  다시 적었습니다.
- **MinIO v2 클러스터 메트릭은 약 10초 늦습니다.** runner는 v3 API 메트릭을 씁니다. 그러지 않으면
  읽은 바이트가 다음 쿼리 행에 기록됩니다.
- **MinIO 이미지:** `minio/minio`가 Docker Hub 배포를 중단해서 `bitnamilegacy/minio`로 고정했습니다.
- **`max_worker_processes = 16`.** PG18의 io worker, 병렬 worker, pg_lake의 문장별 worker가 기본
  풀 8개를 같이 씁니다. 값을 올리기 전에는 SF10 tiering이 `out of background worker slots`로
  실패했습니다.
- **bulk 기록은 연도별로 커밋합니다.** `lineitem_cold`에 5,400만 행을 파티션 `INSERT` 한 번으로
  쓰면 pg-main이 4 GB 한도에서 OOM으로 종료됐습니다.
- **dbgen은 nation·region까지 모든 테이블을 쪼갭니다.** `children > 1`이면 조각마다 일부만 들어
  있어서, `datagen/gen.py`는 두 테이블을 별도 실행으로 통째로 씁니다.

### 📝 라이선스

[MIT](../../LICENSE). `images/pg-main/patches/`의 pg_lake 패치는 pg_lake(Apache-2.0)에 대한 변경이며,
같은 라이선스로 업스트림에 제안했습니다.

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2026-09-25
