# Aggregating materialized views over ReplacingMergeTree

[English](#english) | [한국어](#한국어)

---

## English

An incremental materialized view runs on each insert block. It never sees a merge. Over a `ReplacingMergeTree`
source this means every new version of a key is aggregated again, an older version that arrives late is counted
too, and a delete marker is one more row, while the source itself ends up right after a merge or with `FINAL`.
This lab reproduces each of those cases on small data, compares seven designs that avoid them on the same
history, measures what they cost at 10M orders, and measures how many superseded rows a table carries under
continuous upserts with 1 or 4 CPUs and with `min_age_to_force_merge_seconds`.

The basics of `ReplacingMergeTree` and `FINAL` (with and without, `OPTIMIZE`, `argMax`) are in
[workload/replacingmergetree](../replacingmergetree/); how `FINAL` changed between versions is in
[workload/final-across-versions](../final-across-versions/). This lab does not repeat them.

### Run it

```bash
cd workload/replacingmergetree-mv
grep -v '^#' versions.txt | xargs -I{} docker pull clickhouse/clickhouse-server:{}
./run_matrix.py                    # 26.8 LTS and 26.10, a fresh container per build -> results/<build>.json, RESULTS.md
./run_matrix.py --versions 26.10   # one build
./headroom.py                      # four containers (1 or 4 CPUs, forced merges off or on), about 3 minutes each -> HEADROOM.md
./headroom.py --batch 200000       # four times the rows per INSERT (800k rows/s)
tools/hol run workload/replacingmergetree-mv   # from the repository root: every NN-*.sql once, must not raise
```

`run_matrix.py` is the same runner as in [final-across-versions](../final-across-versions/) (identical file):
each statement runs in its own `clickhouse-client` call, a statement preceded by `-- probe:` is measured and its
`system.query_log` row kept. `errors/` holds a probe that is expected to fail; `tools/hol` does not run it.
`headroom.py` needs only Docker; it starts its own containers (`rmtmv-headroom-<cpus>`) with `--cpus`.

### Files

| File | What it does |
|---|---|
| `01-double-count.sql` | `orders` (`ReplacingMergeTree(ver)`), a per-day `SummingMergeTree` MV and a per-day `AggregatingMergeTree` MV with `uniqExact(order_id)`; three orders, then three corrections; source with and without `FINAL`, both targets, the target's rows by part; `OPTIMIZE … FINAL` on the source, then on the target |
| `02-late-and-ties.sql` | v1, v3, then a late v2 of one order; the per-day MV against a per-key `argMaxState(…, ver)` target; two different rows with the same version: `FINAL` against `argMaxMerge` before and after the target merges |
| `03-group-change-delete.sql` | `ReplacingMergeTree(ver, is_deleted)`; status `pending` → `paid` → `refunded` and a delete; a per-status MV with and without `WHERE is_deleted = 0`; the delete marker after `OPTIMIZE … FINAL` and after `… FINAL CLEANUP` |
| `04-blocks-and-retries.sql` | two versions of one key in one insert block (`optimize_on_insert`); a retried identical insert without a deduplication window, with `non_replicated_deduplication_window` on source and target, with `deduplicate_blocks_in_dependent_materialized_views = 0`; a different order whose MV output block is identical |
| `05-strategies.sql` | one history with an update, a late version, a key moving to another day and a delete, read through: N naive MV, A per-key `argMaxState` + query-time rollup, B writer-side retraction rows (`sign`), C refreshable MV over `FINAL`, D partition rebuild (`REPLACE PARTITION`), E query-time `argMax` on the source, F `OPTIMIZE … FINAL` then a plain read |
| `06-scale.sql` | 10M orders + 2M updates + 2M regrouped + 1M updates + 1M late versions + 200k deletes (16.2M rows, merges stopped): totals of every design, per-day report time for N, `FINAL`, A and E (3 runs), one full refresh, one-day rebuild, storage, insert cost of a 2M-row batch with no MV / naive MV / per-key MV, `OPTIMIZE … FINAL`, reads on one part |
| `errors/01-mv-final.sql` | `FINAL` in the `SELECT` of an incremental MV (rejected, Code 397) |
| `headroom.py` | 2M keys, then 50k random-key upserts every 0.25 s for 60 s, then 60 s idle; superseded rows (`system.parts` rows − keys), parts and running merges every second; `count() FINAL` and `OPTIMIZE … FINAL` time at the end |
| `99-cleanup.sql` | drops the `rmt_mv` database |

### Results

Verified on ClickHouse 26.8.36.3 and 26.10.3.7 (`clickhouse/clickhouse-server:<tag>`), 2026-11-07, Apple M4 Pro
host, Docker Desktop VM with 12 CPUs and 7.7 GiB, a fresh container per build. Containers of another lab were
running at the same time; their CPU% is in [RESULTS.md](RESULTS.md) and [HEADROOM.md](HEADROOM.md). Every number
below is copied from those two files.

**What the MV target holds** (`01`–`04`, identical on both builds):

| Case | Source `FINAL` (truth) | MV target |
|---|---|---|
| 3 orders, one corrected once, one twice | 3 · 670 | 6 · 1,220 (`uniqExact` target: 3 · 1,220) |
| … after `OPTIMIZE … FINAL` on source and target | 3 · 670 | 6 · 1,220 |
| v1, v3, then a late v2 | 1 · 130 | 3 · 350 |
| `pending` → `paid` → `refunded` + one delete | paid 1 · refunded 1 | pending 4 · paid 2 · refunded 1 (with `WHERE is_deleted = 0`: pending 3) |
| two versions in one insert block | 2 rows in the part | 3 · 450 |
| retried insert, no deduplication window | 1 · 100 | 2 · 200 |
| retried insert, `deduplicate_blocks_in_dependent_materialized_views = 0` | 3 rows | 4 · 400 |
| `FINAL` in the MV `SELECT` | — | ✗ Code 397 |

Two rows with the same version: `FINAL` returns the one inserted last (900); a per-key `argMaxState` target
returns 900 before it merges and 500 after `OPTIMIZE … FINAL`.

**Seven designs on one history** (`05`, truth 11-01 = 3 · 870, 11-02 = 1 · 300): the naive per-day MV gives
11-01 = 8 · 2,080. Per-key `argMaxState`, writer-side retraction rows, the refreshable MV (after a refresh), the
partition rebuild and query-time `argMax` all return the truth; `OPTIMIZE … FINAL` then a plain read is right until
the next insert (4 · 1,420 after one more correction).

**Cost at 10M orders / 16.2M rows, 16 parts** (`06`, median of 3, 26.8.36.3 / 26.10.3.7):

| Read or write | Time · memory | Answer |
|---|---|---|
| naive per-day MV target | 0.00 s · 2 MiB / same | 16,000,000 orders · 87,981,600,000 (wrong) |
| source `FINAL` per day | 0.15 s · 94 MiB / 0.21 s · 73 MiB | 9,800,000 · 53,898,480,000 |
| per-key `argMaxState` target, rolled up | 3.00 s · 2,536 MiB / 3.14 s · 2,469 MiB | right |
| `argMax … GROUP BY order_id` on the source | 0.27 s · 849 MiB / 0.41 s · 826 MiB | right |
| one full refresh (`INSERT … SELECT … FINAL`) | 0.14 s / 0.25 s | right |
| one-day rebuild (`FINAL WHERE day = …`, reads every key) | 0.14 s / 0.26 s | right |
| `OPTIMIZE TABLE orders FINAL` → 1 part | 1.87 s / 1.89 s | then `FINAL` 0.03 s, plain 0.02 s |
| INSERT 2M rows: no MV / naive MV / per-key MV | 0.14 / 0.16 / 1.40 s — 0.16 / 0.17 / 1.34 s | per-key MV 1,046 MiB |

Sizes: `orders` 16.2M rows 105.49 MiB, `order_state` 14.7M rows 111.80 MiB, naive target 30 rows 401 B.

**Merge headroom** (`headroom.py`, 26.10.3.7, 2M keys): without forced merges, every configuration (1 or 4 CPUs,
200k or 800k rows/s) still had 2,951,900–3,697,026 superseded rows in 6–7 parts 60 s after ingest stopped; with
`min_age_to_force_merge_seconds = 20` every configuration reached 1 part and 0 superseded rows about 41 s after
ingest. 1 vs 4 CPUs barely changed the superseded count; it changed the maximum insert latency at 800k rows/s
(0.75 s vs 0.22 s) and `count() FINAL` at the end of ingest (0.29–0.31 s vs 0.14–0.17 s). Full table:
[HEADROOM.md](HEADROOM.md).

### Screens

Captured 2026-11-07 from `/play` on a local 26.10.3.7 container loaded with this lab's files, for the notes
article `core-architecture/replacingmergetree-materialized-view`:

- [`images/01-double-count-26-10.png`](images/01-double-count-26-10.png) — `01` before any merge: source `FINAL` 3 · 670, source without `FINAL` 6 · 1,220, `SummingMergeTree` target 6 · 1,220, `uniqExact` target 3 · 1,220
- [`images/02-scale-totals-26-10.png`](images/02-scale-totals-26-10.png) — `06` after `OPTIMIZE … FINAL`: source with and without `FINAL` 9,800,000 · 53,898,480,000, per-day MV target 16,000,000 · 87,981,600,000, per-key target 9,800,000 · 53,898,480,000

### Not verified here

- ClickHouse Cloud (SharedMergeTree): deduplication window defaults and merge behaviour were not run
- Concurrent inserts during a partition rebuild (`REPLACE PARTITION` racing the MV)
- Merge headroom on tables large enough that a single merge takes minutes

---

## 한국어

증분 MV는 INSERT 블록마다 돌고 병합은 보지 못합니다. 원본이 `ReplacingMergeTree`이면 키의 새 버전이 들어올 때마다
다시 집계되고, 늦게 온 옛 버전도 더해지며, 삭제 표시도 한 행으로 셉니다. 원본은 병합이나 `FINAL`로 맞아지는데
대상은 그대로입니다. 이 실습은 각 경우를 작은 데이터로 재현하고, 이를 피하는 설계 일곱 가지를 같은 이력에서 비교하고,
1,000만 주문에서 비용을 재고, 계속되는 upsert에서 CPU 1개 · 4개와 `min_age_to_force_merge_seconds`에 따라
대체된 행이 얼마나 남는지 잽니다.

`ReplacingMergeTree`와 `FINAL`의 기초는 [workload/replacingmergetree](../replacingmergetree/), `FINAL`의 버전별
변화는 [workload/final-across-versions](../final-across-versions/)에 있습니다.

### 실행

```bash
cd workload/replacingmergetree-mv
grep -v '^#' versions.txt | xargs -I{} docker pull clickhouse/clickhouse-server:{}
./run_matrix.py                    # 26.8 LTS, 26.10 — 빌드마다 새 컨테이너 -> results/<빌드>.json, RESULTS.md
./headroom.py                      # CPU 1 · 4 × 강제 병합 끔 · 켬, 조합마다 약 3분 -> HEADROOM.md
./headroom.py --batch 200000       # INSERT당 행 4배(초당 80만 행)
tools/hol run workload/replacingmergetree-mv   # 저장소 루트에서: NN-*.sql을 한 번씩, 실패 없어야 함
```

### 파일

| 파일 | 하는 일 |
|---|---|
| `01-double-count.sql` | 주문 3건과 정정 3번; 일별 `SummingMergeTree` MV, `uniqExact` 대상; 원본 · 대상 `OPTIMIZE … FINAL` |
| `02-late-and-ties.sql` | v1, v3, 늦은 v2; 키 단위 `argMaxState` 대상; 같은 버전 두 행 |
| `03-group-change-delete.sql` | 상태 변경과 `is_deleted` 삭제; MV에서 삭제 표시 거르기; `FINAL CLEANUP` |
| `04-blocks-and-retries.sql` | 한 블록 안의 두 버전; 재시도와 중복 제거 창, `deduplicate_blocks_in_dependent_materialized_views` |
| `05-strategies.sql` | 위험 네 가지가 든 한 이력을 일곱 설계로 읽기 |
| `06-scale.sql` | 1,620만 행(병합 멈춤)에서 설계별 합계 · 조회 · 갱신 · 재빌드 · INSERT 비용, `OPTIMIZE … FINAL` 뒤 |
| `errors/01-mv-final.sql` | MV `SELECT`의 `FINAL`(Code 397로 거부) |
| `headroom.py` | 키 200만 개에 0.25초마다 임의 키 upsert 60초, 60초 휴식; 1초마다 대체된 행 · 파트 |
| `99-cleanup.sql` | `rmt_mv` 데이터베이스 삭제 |

### 결과

26.8.36.3과 26.10.3.7에서 2026-11-07에 실행했습니다(Apple M4 Pro, Docker VM 12 CPU · 7.7 GiB, 빌드마다 새
컨테이너, 다른 실습의 컨테이너가 함께 돌았고 그 CPU%는 [RESULTS.md](RESULTS.md) · [HEADROOM.md](HEADROOM.md)에
있음). 표와 해석은 노트 글 [ReplacingMergeTree와 집계 MV](https://clickhouse.litkhai.dev/articles/core-architecture/replacingmergetree-materialized-view/)에
있고, 모든 수치는 위 두 파일에서 옮겼습니다.

- MV 대상은 정정 · 늦은 버전 · 그룹 변경 · 삭제 · 블록 안 중복 · 창 없는 재시도를 모두 한 번 더 셉니다(주문 3건 · 670이 6건 · 1,220). 원본과 대상을 `OPTIMIZE … FINAL`해도 그대로입니다
- 같은 이력에서 키 단위 `argMaxState`, 상쇄 행, refreshable MV, 파티션 재빌드, 조회 때 `argMax`가 정답이었습니다
- 1,620만 행에서 일별 보고서: 원본 `FINAL` 0.15–0.21초, 키 단위 상태 3.0–3.1초 · 2.5 GiB, 원본 `argMax` 0.27–0.41초. 키 단위 MV는 200만 행 INSERT를 0.16초에서 1.34–1.40초로 늘렸습니다
- 강제 병합 없이는 INSERT가 끝나고 60초 뒤에도 대체된 행 295만–370만 개가 남았고, `min_age_to_force_merge_seconds = 20`이면 약 41초 뒤 0이었습니다. CPU 1개와 4개는 대체된 행 수를 거의 바꾸지 않았습니다

### 여기서 확인하지 않은 것

- ClickHouse Cloud(SharedMergeTree)의 중복 제거 창 기본값과 병합
- 파티션 재빌드 중 동시에 들어오는 INSERT(`REPLACE PARTITION`과 MV의 경합)
- 병합 하나가 몇 분씩 걸리는 큰 테이블의 병합 여유

---

## License

[MIT](../../LICENSE) — same as the rest of the repository.

## 라이선스

[MIT](../../LICENSE) — 저장소 전체와 동일합니다.
