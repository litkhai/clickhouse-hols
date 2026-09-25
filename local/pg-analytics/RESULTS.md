# Results — pg_duckdb vs pg_clickhouse on pg_lake's Iceberg (TPC-H SF10)

[English](#english) | [한국어](#한국어)

## English

Light run (`./run-all.sh 10`) on 2026-09-25, macOS Docker VM with 12 vCPU / 7.7 GB;
every engine container capped at 4 CPU / 4 GB. Raw rows are in
`results/sf10/bench.csv`, plans in `results/sf10/plans/`, the generated tables in
[results/SUMMARY.md](results/SUMMARY.md). A write-up for readers is in
[blog/](blog/).

| Path | Versions |
|---|---|
| A pg_lake native (correctness reference) | PostgreSQL 18.6, pg_lake 3.5.3 (+ manifest patch), pgduck_server DuckDB v1.5.5 |
| B pg_duckdb release | `pgduckdb/pgduckdb:18-v1.1.1` (DuckDB v1.4.3) — Q6 and C1 only |
| B′ pg_duckdb main | `pgduckdb/pgduckdb:18-main`, pg_duckdb 1.2.0-dev, DuckDB v1.5.4 |
| C pg_clickhouse → ClickHouse | pg_clickhouse 0.10.0, ClickHouse 26.9.1.1629 `DataLakeCatalog` |

All paths read the same Iceberg snapshot through Apache Polaris 1.7.0: 73 monthly
files for `lineitem_cold` (53.9 M rows, 1.8 GB) and `orders_cold` (13.9 M rows).
Rows from 1998-02 on stay in PG heap. Q1–Q18 and C1–C4 read only the Iceberg
tier; C5 and C6 union heap and Iceberg. Dimensions are Iceberg copies (D1).
A, B′ and C ran back to back in one invocation; each number is the median of 5
warm runs after one untimed warm-up.

### 1. Can pg_clickhouse read pg_lake's Iceberg files?

**Yes, but only with a pg_lake fix.** Stock pg_lake 3.5.3 writes manifests
without the key-value metadata the Iceberg spec requires, and ClickHouse rejects
them (`No partition-spec in iceberg manifest file`). With the patch in
`images/pg-main/patches/` (reported as
[pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659)), all nine
queries return results identical to path A. Six are pushed down whole
(`Remote SQL` in the plan); Q18, C5 and C6 are pushed down in part.

### 2. Warm latency (p50, min–max of 5 runs)

| Tier | Query | A pg_lake | B′ pg_duckdb | C pg_clickhouse | C pushdown |
|---|---|---:|---:|---:|---|
| L1 | Q1 pricing summary | 921 ms | **625 ms** (605–667) | 797 ms (733–1031) | full |
| L1 | Q6 revenue forecast | 233 ms | **65 ms** (65–68) | 116 ms (107–147) | full |
| L1 | C1 monthly count, one quarter | 327 ms | 166 ms (164–187) | **30 ms** (29–44) | full |
| L2 | C2 top 100 customers | 524 ms | 270 ms (267–316) | **175 ms** (150–217) | full |
| L3 | Q3 shipping priority | 799 ms | **278 ms** (266–314) | 3.85 s (2.88–3.94) | full |
| L3 | Q5 local supplier volume | 934 ms | **487 ms** (464–499) | 863 ms (719–1074) | full |
| L4 | Q18 large volume customer | 2.09 s | **1.09 s** (1.08–1.12) | 22.2 s (21.8–27.2) | partial |
| L5 | C5 last 12 months (hot + cold) | 844 ms | **200 ms** (190–232) | 636 ms (596–666) | partial |
| L5 | C6 point lookup (hot + cold) | 347 ms | 82 ms (81–91) | **77 ms** (67–91) | partial |

Tier geomeans (A / B′ / C): L1 412 / 189 / **141 ms**, L2 524 / 270 / **175 ms**,
L3 864 / **368 ms** / 1.82 s, L4 2.09 / **1.09** / 22.2 s, L5 542 / **129** / 221 ms.

![per-query latency](results/charts/query_latency_sf10.png)

### 3. Load on the main Postgres node (median core-seconds per warm query)

| Query | A pg-main | C pg-main | C ClickHouse | B′ (separate node) |
|---|---:|---:|---:|---:|
| Q1 | 2.81 | 0.01 | 3.10 | 2.34 |
| Q6 | 0.34 | 0.01 | 0.29 | 0.13 |
| C1 | 0.71 | 0.01 | 0.03 | 0.52 |
| C2 | 1.35 | 0.01 | 0.58 | 0.94 |
| Q3 | 1.47 | 0.03 | 6.86 | 0.77 |
| Q5 | 2.07 | 0.01 | 2.86 | 1.37 |
| Q18 | 5.23 | **14.04** | 26.12 | 4.03 |
| C5 | 1.33 | 0.62 | 0.10 | 0.73 |
| C6 | 0.45 | 0.01 | 0.06 | 0.13 |

When a query is pushed down whole, C costs the main node 0.01–0.03 core-seconds.
A runs everything on the main node; B′ moves the work to a second Postgres that
holds a copy of the hot rows.

### 4. Where C loses time

**Q3: ClickHouse's join order, not the FDW.** Run straight in ClickHouse, Q3's
`Remote SQL` takes 3.5–3.7 s — the same as through pg_clickhouse. ClickHouse
builds the hash table from the right side of the join, and the pushed-down
query lists `lineitem_cold` last. `query_plan_join_swap_table` is `auto` by
default, but it did not swap here; our reading is that it lacks row estimates
for Iceberg tables. Forcing the swap takes Q3 to 0.68–0.73 s in ClickHouse.

**Q18: the `IN (… GROUP BY … HAVING)` semi-join is not pushed down.**
pg_clickhouse 0.10.0 pushes the three-table join and the subquery as two
separate remote queries. ClickHouse then streams the joined 54 M-row result
back, and Postgres does the semi-join: 22 s, and 14 core-seconds on the main
node. Rewriting the `IN` as a join to the aggregated subquery gives the same
plan. The same Q18 run inside ClickHouse takes 3.8–4.6 s.

### 5. Tuning path C: `query_plan_join_swap_table 1`

pg_clickhouse passes ClickHouse settings through
`pg_clickhouse.session_settings`. Path C was re-run with its defaults plus
`query_plan_join_swap_table 1` (`--resource-mode join-swap`):

| Query | C default | C + join swap | B′ |
|---|---:|---:|---:|
| Q3 | 3.85 s | **608 ms** | 278 ms |
| Q5 | 863 ms | 811 ms | 487 ms |
| Q18 | 22.2 s | 20.2 s | 1.09 s |
| C6 | 77 ms | 61 ms | 82 ms |

Only Q3 changes meaningfully (6.3×). Queries without joins moved by up to ±30 %
between the two runs (Q6 116 → 153 ms, C2 175 → 252 ms). That is run-to-run
noise on this VM, and it is the error bar for every number here.

For Q18, the work has to go to ClickHouse as one query. Measured by hand with
psql `\timing` (3 runs), not by the harness:
- We wrapped the `IN` in a ClickHouse view (`orders_big`) and imported it as a
  foreign table. The whole query was then pushed down, with identical results,
  in 8.2–8.9 s.
- Adding the join swap brought it to 4.2 s.

### 6. Findings

1. **pg_lake manifests break spec-strict readers.** The ClickHouse path does
   not work on stock pg_lake 3.5.3; see §1.
2. **pg_duckdb 1.1.1 returns wrong results on `month()`-partitioned tables.**
   Q6 differs from A, and C1 returns 0 rows instead of 3. The DuckDB iceberg
   extension it ships computes the month transform as days/30 and prunes live
   files ([duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699)).
   The fix is on pg_duckdb main only, so we asked for a release
   ([pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083)). B′ is that
   main build.
3. **pg_clickhouse before v0.10.0 can crash or return wrong rows** when two of
   its scans are open inside one join.
   - This lab first pinned v0.3.2. There, C6 killed the backend with SIGSEGV,
     and a reduced nested loop over two foreign scans returned 0 rows instead
     of 4.
   - Upstream fixed it in v0.10.0 (commit `dcec30b`: concurrent scans no longer
     share one binary-driver connection). We reproduced it on 0.3.2 and not on
     0.10.0, so no issue was filed.
4. **Join order is the biggest tuning knob for C on Iceberg** (§4, §5).
5. **A semi-join that is not pushed down turns C into the slowest path, and the
   heaviest on the main node** (Q18).

### 7. What was not run

This is the light scenario of [docs/DESIGN.md](docs/DESIGN.md). It did not run:
- cold-cache runs, or D2 (dimensions in heap);
- the concurrency, fault-injection or ILM-ops phases;
- the monthly tiering job (cold months were written by `setup.py --bulk`,
  458 s at SF10);
- SF1 or SF30.

The scripts for those phases are in the lab, but none of these numbers came
from them.

---

## 한국어

2026-09-25 경량 실행(`./run-all.sh 10`) 결과입니다. macOS Docker VM(12 vCPU / 7.7 GB)에서
엔진 컨테이너마다 4 CPU / 4 GB로 제한했습니다. 원자료는 `results/sf10/bench.csv`, 실행 계획은
`results/sf10/plans/`, 자동 생성 표는 [results/SUMMARY.md](results/SUMMARY.md)에 있습니다.
독자용 글은 [blog/](blog/)에 있습니다.

| 경로 | 버전 |
|---|---|
| A pg_lake 네이티브 (정답 기준) | PostgreSQL 18.6, pg_lake 3.5.3(+ manifest 패치), pgduck_server DuckDB v1.5.5 |
| B pg_duckdb 릴리스 | `pgduckdb/pgduckdb:18-v1.1.1`(DuckDB v1.4.3) — Q6, C1만 |
| B′ pg_duckdb main | `pgduckdb/pgduckdb:18-main`, pg_duckdb 1.2.0-dev, DuckDB v1.5.4 |
| C pg_clickhouse → ClickHouse | pg_clickhouse 0.10.0, ClickHouse 26.9.1.1629 `DataLakeCatalog` |

모든 경로가 Apache Polaris 1.7.0을 거쳐 같은 Iceberg 스냅샷을 읽습니다.
`lineitem_cold`(5,390만 행, 1.8 GB)와 `orders_cold`(1,390만 행)는 월별 파일 73개입니다.
1998-02 이후 행은 PG heap에 남습니다. Q1–Q18과 C1–C4는 Iceberg 계층만 읽고, C5·C6은 heap과
Iceberg를 합쳐 읽습니다. 디멘션은 Iceberg 사본(D1)입니다. A, B′, C는 한 번의 실행에서 연달아
측정했고, 각 수치는 측정하지 않는 warm-up 1회 뒤 warm 5회의 중앙값입니다.

### 1. pg_clickhouse로 pg_lake의 Iceberg 파일을 읽을 수 있는가?

**읽을 수 있지만, pg_lake를 고쳐야 합니다.** 순정 pg_lake 3.5.3은 Iceberg 스펙이 요구하는
key-value 메타데이터 없이 manifest를 쓰고, ClickHouse는 이를 거부합니다(`No partition-spec in
iceberg manifest file`). `images/pg-main/patches/`의 패치
([pg_lake#659](https://github.com/Snowflake-Labs/pg_lake/issues/659)로 보고)를 적용하면 쿼리 9개
모두 경로 A와 같은 결과를 냅니다. 6개는 통째로 ClickHouse로 넘어가고(계획의 `Remote SQL`),
Q18·C5·C6은 일부만 넘어갑니다.

### 2. warm 지연시간 (p50, 5회의 최소–최대)

| Tier | 쿼리 | A pg_lake | B′ pg_duckdb | C pg_clickhouse | C pushdown |
|---|---|---:|---:|---:|---|
| L1 | Q1 가격 요약 | 921 ms | **625 ms** (605–667) | 797 ms (733–1031) | full |
| L1 | Q6 매출 예측 | 233 ms | **65 ms** (65–68) | 116 ms (107–147) | full |
| L1 | C1 분기 내 월별 건수 | 327 ms | 166 ms (164–187) | **30 ms** (29–44) | full |
| L2 | C2 고객 Top 100 | 524 ms | 270 ms (267–316) | **175 ms** (150–217) | full |
| L3 | Q3 배송 우선순위 | 799 ms | **278 ms** (266–314) | 3.85 s (2.88–3.94) | full |
| L3 | Q5 지역 공급자 매출 | 934 ms | **487 ms** (464–499) | 863 ms (719–1074) | full |
| L4 | Q18 대량 구매 고객 | 2.09 s | **1.09 s** (1.08–1.12) | 22.2 s (21.8–27.2) | partial |
| L5 | C5 최근 12개월(hot + cold) | 844 ms | **200 ms** (190–232) | 636 ms (596–666) | partial |
| L5 | C6 키 단건 조회(hot + cold) | 347 ms | 82 ms (81–91) | **77 ms** (67–91) | partial |

Tier별 기하평균(A / B′ / C): L1 412 / 189 / **141 ms**, L2 524 / 270 / **175 ms**,
L3 864 / **368 ms** / 1.82 s, L4 2.09 / **1.09** / 22.2 s, L5 542 / **129** / 221 ms.

### 3. 메인 Postgres 노드 부하 (warm 쿼리당 core-초 중앙값)

| 쿼리 | A pg-main | C pg-main | C ClickHouse | B′ (별도 노드) |
|---|---:|---:|---:|---:|
| Q1 | 2.81 | 0.01 | 3.10 | 2.34 |
| Q6 | 0.34 | 0.01 | 0.29 | 0.13 |
| C1 | 0.71 | 0.01 | 0.03 | 0.52 |
| C2 | 1.35 | 0.01 | 0.58 | 0.94 |
| Q3 | 1.47 | 0.03 | 6.86 | 0.77 |
| Q5 | 2.07 | 0.01 | 2.86 | 1.37 |
| Q18 | 5.23 | **14.04** | 26.12 | 4.03 |
| C5 | 1.33 | 0.62 | 0.10 | 0.73 |
| C6 | 0.45 | 0.01 | 0.06 | 0.13 |

쿼리가 통째로 pushdown되면 C가 메인 노드에 주는 부하는 0.01–0.03 core-초입니다. A는 전부
메인 노드에서 돌리고, B′는 hot 행 사본을 가진 두 번째 Postgres로 일을 옮깁니다.

### 4. C가 시간을 잃는 곳

**Q3: FDW가 아니라 ClickHouse의 조인 순서입니다.** Q3의 `Remote SQL`을 ClickHouse에서 직접
돌려도 3.5–3.7초로, pg_clickhouse를 거칠 때와 같습니다. ClickHouse는 조인 오른쪽으로 해시
테이블을 만드는데, pushdown된 쿼리는 `lineitem_cold`를 맨 뒤에 둡니다.
`query_plan_join_swap_table` 기본값은 `auto`인데 여기서는 바꾸지 않았습니다. Iceberg 테이블의
행 수 추정치가 없어서 그런 것으로 봅니다. 강제로 바꾸면 ClickHouse에서 Q3가 0.68–0.73초입니다.

**Q18: `IN (… GROUP BY … HAVING)` semi-join이 pushdown되지 않습니다.** pg_clickhouse 0.10.0은
3-way 조인과 서브쿼리를 원격 쿼리 두 개로 따로 넘깁니다. 그러면 ClickHouse가 조인 결과
5,400만 행을 돌려보내고, semi-join은 Postgres가 합니다. 22초가 걸리고 메인 노드가 14 core-초를
씁니다. `IN`을 집계 서브쿼리와의 조인으로 바꿔 써도 계획은 같습니다. 같은 Q18을 ClickHouse
안에서 돌리면 3.8–4.6초입니다.

### 5. 경로 C 튜닝: `query_plan_join_swap_table 1`

pg_clickhouse는 `pg_clickhouse.session_settings`로 ClickHouse 설정을 넘깁니다. 기본값에
`query_plan_join_swap_table 1`만 더해 경로 C를 다시 돌렸습니다(`--resource-mode join-swap`).

| 쿼리 | C 기본 | C + join swap | B′ |
|---|---:|---:|---:|
| Q3 | 3.85 s | **608 ms** | 278 ms |
| Q5 | 863 ms | 811 ms | 487 ms |
| Q18 | 22.2 s | 20.2 s | 1.09 s |
| C6 | 77 ms | 61 ms | 82 ms |

의미 있게 바뀐 것은 Q3뿐입니다(6.3배). 조인이 없는 쿼리도 두 실행 사이에 최대 ±30 %
움직였습니다(Q6 116 → 153 ms, C2 175 → 252 ms). 이 VM의 실행 간 노이즈이고, 이 문서의 모든
수치에 붙는 오차 범위입니다.

Q18은 작업을 한 쿼리로 ClickHouse에 넘겨야 빨라집니다. 아래는 하니스가 아니라 psql
`\timing`으로 직접 잰 값입니다(3회).
- `IN`을 ClickHouse 뷰(`orders_big`)로 감싸 foreign table로 가져왔습니다. 그러자 쿼리 전체가
  pushdown됐고, 결과는 같았으며, 8.2–8.9초가 걸렸습니다.
- 여기에 join swap을 더하자 4.2초가 됐습니다.

### 6. 발견 사항

1. **pg_lake manifest는 스펙을 엄격히 지키는 리더에서 깨집니다.** 순정 pg_lake 3.5.3에서는
   ClickHouse 경로가 동작하지 않습니다. §1 참고.
2. **pg_duckdb 1.1.1은 `month()` 파티션 테이블에서 틀린 결과를 냅니다.** Q6가 A와 다르고,
   C1은 3행 대신 0행을 반환합니다. 함께 배포되는 DuckDB iceberg 확장이 month 변환을 days/30으로
   계산해 살아 있는 파일을 pruning합니다([duckdb-iceberg#699](https://github.com/duckdb/duckdb-iceberg/issues/699)).
   수정은 pg_duckdb main에만 있어 릴리스를 요청했습니다
   ([pg_duckdb#1083](https://github.com/duckdb/pg_duckdb/issues/1083)). B′가 그 main 빌드입니다.
3. **v0.10.0 이전 pg_clickhouse는 한 조인 안에서 스캔 두 개가 열리면 죽거나 틀린 행을 냅니다.**
   - 이 실습은 처음에 v0.3.2를 고정했습니다. 거기서는 C6에서 backend가 SIGSEGV로 죽었고, 축소판
     (foreign scan 두 개의 nested loop)은 4행이어야 할 결과가 0행이었습니다.
   - 업스트림 v0.10.0에서 고쳐졌습니다(커밋 `dcec30b`: 동시 스캔이 binary driver 연결 하나를 같이
     쓰지 않음). 0.3.2에서는 재현되고 0.10.0에서는 재현되지 않아 이슈는 올리지 않았습니다.
4. **Iceberg 위의 C에서 가장 큰 튜닝 포인트는 조인 순서입니다**(§4, §5).
5. **semi-join이 pushdown되지 않으면 C는 가장 느리고 메인 노드 부하도 가장 큰 경로가 됩니다**(Q18).

### 7. 실행하지 않은 것

[docs/DESIGN.md](docs/DESIGN.md)의 경량 시나리오입니다. 다음은 돌리지 않았습니다.
- cold 캐시 실행, D2(디멘션을 heap에서 읽는 경우)
- 동시성·장애 주입·ILM 운영 단계
- 월 단위 tiering 작업(cold 월은 `setup.py --bulk`로 기록, SF10에서 458초)
- SF1·SF30

해당 단계 스크립트는 실습에 있지만, 이 문서의 수치는 그 스크립트에서 나오지 않았습니다.
