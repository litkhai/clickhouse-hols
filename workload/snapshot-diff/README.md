# Diffing hourly full snapshots: new, changed and deleted records

[English](#english) | [한국어](#한국어)

---

## English

A source re-delivers a **full snapshot** every hour into a plain `MergeTree`, for example through the
ClickHouse Kafka Connect Sink: every record again, one row per record, a `record_key`, 25 `Nullable(String)`
business fields, an `event_timestamp` that moves on every delivery and an `ingestion_timestamp` set when the
row is written. Downstream wants only the records that are **new**, **changed** or **deleted** since the
previous snapshot. This lab builds that diff on ClickHouse Cloud, shows four ways it goes wrong, automates it
with a refreshable materialized view that appends to a changes table, and measures it at 1M and 10M records.

Refreshable MVs in general (`APPEND`, `APPEND INCREMENTAL`, scheduling) are in
[workload/mv-vs-rmv](../mv-vs-rmv/); insert-time MVs over `ReplacingMergeTree` are in
[workload/replacingmergetree-mv](../replacingmergetree-mv/). This lab does not repeat them.

### Run it

```bash
cd workload/snapshot-diff
./run.sh                 # 00 → 06 and errors/01 on a ClickHouse Cloud service, then 99 → results/cloud-<version>.txt
KEEP=1 ./run.sh          # the same, keeping the snapdiff database for screenshots; run 99-cleanup.sql afterwards
./scale.py               # 1M and 10M records x 25 fields, 2 runs per probe → results/scale-<version><tag>.json
local/run.sh 9000        # APPEND INCREMENTAL on a local 26.9+ server → results/local-<version>.txt
```

`run.sh` and `scale.py` read `CH_HOST`, `CH_USER` and `CH_PASSWORD` from an env file (default
`~/.config/khai-harness/secrets/clickhouse-seoul.env`) and never print them. They use `clickhouse client`
when it is on `PATH`, otherwise the `clickhouse/clickhouse-server:26.10.3.7` image through Docker. Each SQL
file runs in one client session with `--echo --ignore-error`; the service hostname is replaced by `<service>`
in every output file. `scale.py` reads duration, rows read and peak memory from `system.query_log` on all
replicas, by query id.

### Files

| File | What it does |
|---|---|
| `00-setup.sql` | database `snapdiff`; `gen(n, v, sid)`, a parameterized view that returns one full snapshot (base `v = 0`, next `v = 1`: 0.3 % of keys gone, 0.5 % added, 1 % with `f03` changed, `f06` from `NULL` to `''` for 1 key in 100,000; five fields 10 % `NULL`); `raw` (`PARTITION BY snapshot_id ORDER BY (snapshot_id, record_key)`, `row_hash` `MATERIALIZED`), `manifest` (one row per finished snapshot with its record count), `changes` (what consumers read) |
| `01-boundary.sql` | two snapshots loaded over 8 minutes each, starting at hh:56, plus one re-delivered batch; what an hourly window on `ingestion_timestamp` holds against `snapshot_id`, and the diff by each |
| `02-row-hash.sql` | `cityHash64` on literals (variadic with `NULL`, `tuple`, shifted strings, `ifNull`); the diff with four hashes: `tuple` of the 25 fields, variadic, `ifNull(f, '')`, `tuple` with `event_timestamp` |
| `03-diff.sql` | the diff: current `LEFT JOIN` previous (`record_key`, `row_hash`) `USING (record_key)` → new / changed, previous `LEFT ANTI JOIN` current keys → deleted; the same classification in one `GROUP BY`; the old and new value of each changed field |
| `04-rmv.sql` | `diff_rmv` (`REFRESH EVERY 1 HOUR OFFSET 30 MINUTE APPEND TO changes`, guarded by the manifest and an `'end'` row per snapshot; the diff in two steps: classify keys by `GROUP BY`, then join only the changed keys to their rows) against `diff_rmv_naive` (newest `snapshot_id` against the one before); a refresh on a 60 % load, after the load, two idle refreshes, a snapshot with no change; what a consumer reads; `system.view_refreshes` on both replicas; every refresh and the rows it wrote (`query_log`); parts per refresh |
| `05-insert-mv.sql` | the insert-time alternative: a `ReplacingMergeTree` state table of the last hash per key, an MV that joins every inserted block to it, and an MV that updates it; the next snapshot in 10 inserts |
| `06-ttl.sql` | `TTL snapshot_id + INTERVAL 3 HOUR` with `ttl_only_drop_parts = 1` on six hourly snapshots; the guarded MV when the previous snapshot has been dropped, against a diff with an empty previous side |
| `errors/01-append-incremental.sql` | `REFRESH … APPEND INCREMENTAL` on a 26.8 service (Code 62, it arrived in 26.9) |
| `local/26.9-append-incremental.sql` | `APPEND INCREMENTAL` on 26.9: the JOIN diff is rejected (Code 36), the one-table `GROUP BY` diff sees only the new rows |
| `scale.py` | 1M and 10M records: load, the JOIN diff and its variants, the `GROUP BY` classification, the two-step diff, the guard, a plain `ORDER BY record_key` table without partitions, one refresh that compares and one with nothing to do, and the insert-time MVs; 2 runs each. `--lean` skips three JOIN variants, `--resume` continues a run that broke off with the snapshots still loaded |
| `99-cleanup.sql` | drops the `snapdiff` database |

### Results

Verified on ClickHouse Cloud 26.8.1.654 (Seoul, ap-northeast-2), 2 replicas of 8 GiB with `max_threads` 2
(`max_server_memory_usage` 6.85 GiB), 2026-11-17, through `clickhouse client` 26.9.6.6. `APPEND INCREMENTAL`
on ClickHouse 26.9.6.6 (official macOS build, one local server), the same day. Every number below is copied
from `results/cloud-26.8.1.654.txt`, `results/scale-*` and `results/local-26.9.6.6.txt`. The service autoscales
(8 to 120 GiB per replica); during the 10M run it moved to 12 GiB replicas, so the scale numbers name the size
they ran on.

**The diff of the next snapshot against the base, 10,000 records** (truth from the generator's rules: 50 new,
101 changed, 30 deleted):

| Case (file) | new | changed | deleted |
|---|---|---|---|
| hourly window on `ingestion_timestamp`, 11:00 against 10:00 (`01`) | 2,487 | 29 | 3,830 |
| `snapshot_id`, one batch re-delivered, no dedupe (`01`) | 61 | 120 | 30 |
| `snapshot_id`, `LIMIT 1 BY record_key` (`01`) | **50** | **101** | **30** |
| hash: `cityHash64(tuple(f01, …, f25))` (`02`) | **50** | **101** | **30** |
| hash: `cityHash64(f01, …, f25)`, `NULL` for 4,217 of 10,020 rows (`02`) | 50 | 57 | 30 |
| hash: `cityHash64(tuple(ifNull(f, '') …))` (`02`) | 50 | 100 | 30 |
| hash: `tuple` with `event_timestamp` (`02`) | 50 | 9,970 | 30 |
| one `GROUP BY` over both snapshots, keys only (`03`) | **50** | **101** | **30** |

`cityHash64(NULL::Nullable(String), 'a')` returns `NULL`; the `tuple` form returns a value and a different one
for `''`. `cityHash64(concat('ab', 'c')) = cityHash64(concat('a', 'bc'))` is true; with `tuple` it is false.

**The refreshable MV** (`04`):

| After | `diff_rmv_naive` | `diff_rmv` (guarded) |
|---|---|---|
| a refresh while 60 % of the 10:00 snapshot was loaded | 25 new · 54 changed · 3,959 deleted | nothing (only the 09:00 `'end'` row) |
| the load finished and the manifest row arrived, one refresh | 75 · 155 · 3,989 (appended on top) | 50 · 101 · 30 + `'end'` |
| two more refreshes with nothing new | — | two refreshes, 0 rows each |
| the 11:00 snapshot, same records as 10:00 | — | one `'end'` row, no change rows |

Rows written per refresh, from `system.query_log`: naive 0 (at `CREATE`), 4,038, 181; guarded 1 (the 09:00
baseline `'end'` row, at `CREATE`), 0, 182, 0, 0, 1. The naive MV appended the full diff on top of the partial
one; with `APPEND`, nothing stops a refresh from writing the same snapshot again, and the `'end'` row is what
makes the guarded MV write each snapshot once. `system.view_refreshes` showed each view on both replicas with
the same `next_refresh_time` (12:30:00 for an 11:42 run: the hour + 30 minutes); `read_rows` and
`written_rows` were filled on one replica only. Each refresh wrote one part to `changes` (182 rows for the
10:00 diff).

**Insert-time MV against a `ReplacingMergeTree` state table** (`05`, `parallel_view_processing` = 1 on the
service): the 10:00 snapshot in 10 inserts gave 50 new and 101 changed, no deletes (30 expected), and the
first snapshot came out as 10,000 new records.

**`APPEND INCREMENTAL`** (26.9.6.6, `local/`): the JOIN diff is rejected with
`Incremental refresh requires exactly one source table (no joins)` (Code 36). The one-table `GROUP BY` form is
accepted, but the refresh after the 10:00 load saw only the rows inserted since the previous refresh, and wrote
all 10,020 records as new. On the 26.8 service the statement does not parse (Code 62).

**TTL** (`06`): with `TTL snapshot_id + INTERVAL 3 HOUR` and `ttl_only_drop_parts = 1`, six hourly snapshots
became three (0, 1 and 2 hours old) after `OPTIMIZE … FINAL`. When the previous snapshot had been dropped from
`raw`, the guarded MV wrote nothing for the next one; the same diff with an empty previous side reports every
record of the next snapshot as new (10,000 here).

#### At 1M and 10M records

One snapshot of 1M records is 170 MB compressed (388 MB uncompressed) in `raw`; 10M is 1.69 GB (3.96 GB).
Three runs, all 2026-11-17 (UTC), logs and JSON in `results/`:

- **run 1** (`scale-run-1.log`, 08:37–08:46): 2 replicas of 8 GiB (6.85 GiB usable), `max_threads` 2. It stopped
  at 10M when a replica was replaced: after the JOIN diffs ran out of memory, the service scaled up.
- **run 2** (`scale-run-2.log`, `scale-26.8.1.654-run-2.json`, 08:48–09:02, `--lean`): during the change (old 8 GiB
  and new replicas side by side). Stopped by a DNS failure on the client side at 10M.
- **run 3** (`scale-run-3.log`, `scale-26.8.1.654-10m-resume.json`, 11:36–11:42, `--lean --resume`): the rest of
  10M on 2 replicas of 12 GiB (10.67 GiB usable), `max_threads` 3.

| Probe | 1M records | 10M records |
|---|---|---|
| JOIN diff (`03`), `row_hash` column | 1.65–5.29 s · 1.31 GiB (run 1) | run 1: ✗ Code 241 both runs (query at 4.10–4.39 GiB when the server reached 6.85 GiB); run 2: ✗ 241 on an 8 GiB replica, then 12.5 s · **6.73 GiB** on a larger one |
| JOIN diff, hash computed at query time | 3.01–4.01 s · 1.13 GiB (run 1) | ✗ Code 241 (run 1) |
| JOIN diff, no `LIMIT 1 BY` | 1.38–2.29 s · 1.31 GiB (run 1) | ✗ Code 241 (run 1) |
| JOIN diff, `full_sorting_merge` (the anti join falls back to hash) | 2.21–4.55 s · 1.50 GiB (run 1) | ✗ Code 241 (run 1) |
| `GROUP BY` classification, keys and hashes only | 0.25–0.32 s · 275 MiB (run 1) | 6.39–11.19 s · 2.47 GiB (run 1); 2.3–3.5 s · 1.96 GiB (runs 2–3) |
| two-step diff (classify, then join the changed keys to their rows) | 1.17–1.33 s · 421–614 MiB (run 2) | 11.1–18.6 s · **1.97 GiB**, 4 runs (runs 2–3) |
| two-step diff on a plain `ORDER BY record_key` table without partitions | 1.20–1.22 s · 633 MiB (run 2) | 10.3–18.3 s · 2.66 GiB (run 3) |
| guard: `uniqExact(record_key)` of one snapshot | 0.09–0.10 s · 111 MiB | 1.12–1.49 s · 784 MiB (run 1); 0.56–1.22 s · 1.02 GiB (run 3) |
| refresh that compares (`diff_rmv`, two-step) | 1.02 s · 602 MiB, wrote 18,011 rows (run 2) | 12.18 s · 1.96 GiB, wrote 180,101 rows (run 3) |
| refresh with nothing to do | 0.13 s · 3 MiB (run 2) | 0.03 s · 3 MiB (run 3) |
| one tenth of a snapshot inserted, no MV | 0.86–0.87 s | 3.65 s · 704 MiB (run 3) |
| the same, with the two insert-time MVs (`05`) | 0.69–1.86 s per tenth · 355 MiB | 10.0–29.7 s per tenth · **5.07 GiB** (run 3) |

The refreshes wrote the truth at both sizes (5,000 · 10,010 · 3,000 and 50,000 · 100,100 · 30,000, plus the
`'end'` rows). The insert-time MVs found the same new and changed records and no deletes. Rows read were the same
for the partitioned table and the plain one here because the table held only the two snapshots being compared;
the plain table's reads grow with every snapshot it keeps, which was not measured.

### What this lab does not check

- The Kafka Connect Sink itself: snapshots are generated with `INSERT … SELECT`, and the re-delivered batch is
  simulated. How the sink's exactly-once mode or retries split batches was not tested.
- How consumers are notified beyond polling `changes`: no Kafka engine table, ClickPipes or webhook.
- Snapshots larger than 10M records, or a service with more memory than 8 GiB per replica.

---

## 한국어

원천이 매시간 **전체 스냅샷**을 일반 `MergeTree`로 다시 보내는 경우입니다(예: ClickHouse Kafka Connect
Sink). 모든 레코드가 매번 다시 오고, 레코드마다 한 행에 `record_key`, `Nullable(String)` 업무 필드 25개,
전달할 때마다 바뀌는 `event_timestamp`, 행을 쓸 때 정해지는 `ingestion_timestamp`가 있습니다. 하위 시스템은
이전 스냅샷 이후 **새로 생긴**, **바뀐**, **사라진** 레코드만 원합니다. 이 실습은 ClickHouse Cloud에서 그
비교를 만들고, 틀어지는 경우 네 가지를 보이고, 변경 테이블에 덧붙이는 refreshable materialized view로
자동화하고, 100만 · 1,000만 레코드에서 비용을 잽니다.

refreshable MV 일반(`APPEND`, `APPEND INCREMENTAL`, 일정)은 [workload/mv-vs-rmv](../mv-vs-rmv/)가,
`ReplacingMergeTree` 위의 INSERT 시점 MV는 [workload/replacingmergetree-mv](../replacingmergetree-mv/)가
다룹니다. 여기서는 반복하지 않습니다.

### 실행

```bash
cd workload/snapshot-diff
./run.sh                 # ClickHouse Cloud 서비스에서 00 → 06, errors/01, 99 → results/cloud-<버전>.txt
KEEP=1 ./run.sh          # 같은 실행, 화면 캡처를 위해 snapdiff 데이터베이스를 남김. 끝나면 99-cleanup.sql 실행
./scale.py               # 100만 · 1,000만 레코드 x 필드 25개, 측정마다 2회 → results/scale-<버전><tag>.json
local/run.sh 9000        # 로컬 26.9 이상 서버에서 APPEND INCREMENTAL → results/local-<버전>.txt
```

`run.sh`와 `scale.py`는 env 파일(기본 `~/.config/khai-harness/secrets/clickhouse-seoul.env`)에서
`CH_HOST`, `CH_USER`, `CH_PASSWORD`를 읽고 출력하지 않습니다. `PATH`에 `clickhouse client`가 있으면 그것을,
없으면 Docker로 `clickhouse/clickhouse-server:26.10.3.7` 이미지를 씁니다. SQL 파일마다 클라이언트 세션
하나로 `--echo --ignore-error` 실행하고, 모든 출력에서 서비스 호스트 이름은 `<service>`로 바꿉니다.
`scale.py`는 시간, 읽은 행, 최대 메모리를 query id로 모든 레플리카의 `system.query_log`에서 읽습니다.

### 파일

| 파일 | 하는 일 |
|---|---|
| `00-setup.sql` | 데이터베이스 `snapdiff`. `gen(n, v, sid)`: 전체 스냅샷 하나를 돌려주는 매개변수 뷰(기준 `v = 0`, 다음 `v = 1`: 키 0.3 % 사라짐, 0.5 % 추가, 1 %는 `f03` 변경, 10만 개 중 1개는 `f06`이 `NULL`에서 `''`로. 필드 다섯 개는 10 %가 `NULL`). `raw`(`PARTITION BY snapshot_id ORDER BY (snapshot_id, record_key)`, `row_hash`는 `MATERIALIZED`), `manifest`(끝난 스냅샷마다 레코드 수 한 행), `changes`(소비자가 읽는 테이블) |
| `01-boundary.sql` | hh:56부터 8분씩 적재되는 스냅샷 두 개와 다시 전달된 배치 하나. `ingestion_timestamp`의 시간 창과 `snapshot_id`가 각각 무엇을 담는지, 각각으로 한 비교 |
| `02-row-hash.sql` | 리터럴로 본 `cityHash64`(`NULL`이 있는 가변 인자, `tuple`, 밀린 문자열, `ifNull`). 해시 네 가지로 한 비교: 필드 25개의 `tuple`, 가변 인자, `ifNull(f, '')`, `event_timestamp`를 넣은 `tuple` |
| `03-diff.sql` | 비교: 현재 `LEFT JOIN` 이전(`record_key`, `row_hash`) `USING (record_key)` → 신규 · 변경, 이전 `LEFT ANTI JOIN` 현재 키 → 삭제. 같은 분류를 `GROUP BY` 하나로. 바뀐 필드의 이전 값과 새 값 |
| `04-rmv.sql` | `diff_rmv`(`REFRESH EVERY 1 HOUR OFFSET 30 MINUTE APPEND TO changes`, manifest와 스냅샷마다 `'end'` 행으로 보호. 비교는 두 단계: `GROUP BY`로 키를 분류한 뒤 바뀐 키만 행과 JOIN)와 `diff_rmv_naive`(가장 새 `snapshot_id`와 그 전 것). 60 % 적재 중의 갱신, 적재 뒤, 할 일이 없는 갱신 두 번, 변경이 없는 스냅샷. 소비자가 읽는 쿼리. 두 레플리카의 `system.view_refreshes`. 갱신마다 쓴 행 수(`query_log`). 갱신당 파트 수 |
| `05-insert-mv.sql` | INSERT 시점 대안: 키마다 마지막 해시를 두는 `ReplacingMergeTree` 상태 테이블, 들어온 블록을 그와 JOIN하는 MV, 상태를 갱신하는 MV. 다음 스냅샷을 INSERT 10번으로 |
| `06-ttl.sql` | 시간별 스냅샷 6개에 `TTL snapshot_id + INTERVAL 3 HOUR`와 `ttl_only_drop_parts = 1`. 이전 스냅샷이 지워졌을 때 보호된 MV, 이전 쪽이 빈 비교와 대조 |
| `errors/01-append-incremental.sql` | 26.8 서비스에서 `REFRESH … APPEND INCREMENTAL`(Code 62, 26.9에서 추가) |
| `local/26.9-append-incremental.sql` | 26.9에서 `APPEND INCREMENTAL`: JOIN 비교는 거부(Code 36), 테이블 하나의 `GROUP BY` 비교는 새 행만 봄 |
| `scale.py` | 100만 · 1,000만 레코드: 적재, JOIN 비교와 변형, `GROUP BY` 분류, 두 단계 비교, 가드, 파티션 없는 `ORDER BY record_key` 테이블, 비교하는 갱신 한 번과 할 일 없는 갱신 한 번, INSERT 시점 MV. 각 2회. `--lean`은 JOIN 변형 세 개를 건너뛰고, `--resume`은 스냅샷을 적재한 채 끊긴 실행을 이어 갑니다 |
| `99-cleanup.sql` | `snapdiff` 데이터베이스 삭제 |

### 결과

ClickHouse Cloud 26.8.1.654(Seoul, ap-northeast-2), 8 GiB 레플리카 2개, `max_threads` 2
(`max_server_memory_usage` 6.85 GiB)에서 2026-11-17에 `clickhouse client` 26.9.6.6으로 검증했습니다.
`APPEND INCREMENTAL`은 같은 날 ClickHouse 26.9.6.6(공식 macOS 빌드, 로컬 서버 하나)에서 실행했습니다. 아래
수치는 모두 `results/cloud-26.8.1.654.txt`, `results/scale-*`, `results/local-26.9.6.6.txt`에서 옮겼습니다.
서비스는 자동 확장(레플리카당 8–120 GiB)이 켜져 있어 1,000만 실행 중에 12 GiB 레플리카로 바뀌었고, 규모 수치에는
돌았던 크기를 함께 적었습니다.

**레코드 1만 개, 다음 스냅샷과 기준 스냅샷의 비교** (생성 규칙에서 나온 정답: 신규 50, 변경 101, 삭제 30):

| 경우(파일) | 신규 | 변경 | 삭제 |
|---|---|---|---|
| `ingestion_timestamp` 시간 창, 11:00과 10:00 비교(`01`) | 2,487 | 29 | 3,830 |
| `snapshot_id`, 배치 하나 재전달, 중복 제거 없음(`01`) | 61 | 120 | 30 |
| `snapshot_id`, `LIMIT 1 BY record_key`(`01`) | **50** | **101** | **30** |
| 해시: `cityHash64(tuple(f01, …, f25))`(`02`) | **50** | **101** | **30** |
| 해시: `cityHash64(f01, …, f25)`, 10,020행 중 4,217행이 `NULL`(`02`) | 50 | 57 | 30 |
| 해시: `cityHash64(tuple(ifNull(f, '') …))`(`02`) | 50 | 100 | 30 |
| 해시: `event_timestamp`를 넣은 `tuple`(`02`) | 50 | 9,970 | 30 |
| 두 스냅샷에 `GROUP BY` 하나, 키만(`03`) | **50** | **101** | **30** |

`cityHash64(NULL::Nullable(String), 'a')`는 `NULL`을 돌려줍니다. `tuple` 형태는 값을 돌려주고 `''`일 때와
다른 값입니다. `cityHash64(concat('ab', 'c')) = cityHash64(concat('a', 'bc'))`는 참이고 `tuple`이면 거짓입니다.

**refreshable MV** (`04`):

| 시점 | `diff_rmv_naive` | `diff_rmv`(보호) |
|---|---|---|
| 10:00 스냅샷이 60 % 적재됐을 때 갱신 | 신규 25 · 변경 54 · 삭제 3,959 | 없음(09:00의 `'end'` 행만) |
| 적재가 끝나고 manifest 행이 온 뒤 갱신 한 번 | 75 · 155 · 3,989(위에 덧붙음) | 50 · 101 · 30 + `'end'` |
| 새것이 없는 갱신 두 번 더 | — | 갱신 두 번, 각각 0행 |
| 11:00 스냅샷, 10:00과 같은 레코드 | — | `'end'` 행 하나, 변경 행 없음 |

`system.query_log`에서 본 갱신마다 쓴 행 수: naive 0(`CREATE` 때), 4,038, 181. 보호된 MV 1(`CREATE` 때 09:00
기준 `'end'` 행), 0, 182, 0, 0, 1. naive MV는 부분 비교 위에 전체 비교를 덧붙였습니다. `APPEND`에서는 갱신이 같은
스냅샷을 다시 쓰는 것을 막는 장치가 없고, 보호된 MV가 스냅샷마다 한 번만 쓰게 하는 것이 `'end'` 행입니다.
`system.view_refreshes`는 두 레플리카 모두에 같은 `next_refresh_time`(11:42 실행에서 12:30:00, 정시 + 30분)으로
뷰를 보였고, `read_rows` · `written_rows`는 한 레플리카에만 찼습니다. 갱신마다 `changes`에 파트 하나를
썼습니다(10:00 비교는 182행).

**`ReplacingMergeTree` 상태 테이블과 INSERT 시점 MV** (`05`, 서비스의 `parallel_view_processing` = 1):
10:00 스냅샷을 INSERT 10번으로 넣으니 신규 50, 변경 101, 삭제 0(정답 30)이었고, 첫 스냅샷은 레코드 10,000개
전부 신규로 나왔습니다.

**`APPEND INCREMENTAL`** (26.9.6.6, `local/`): JOIN 비교는
`Incremental refresh requires exactly one source table (no joins)`(Code 36)로 거부됩니다. 테이블 하나의
`GROUP BY` 형태는 받아들여지지만, 10:00 적재 뒤의 갱신은 직전 갱신 이후 들어온 행만 보고 10,020개를 모두 신규로
썼습니다. 26.8 서비스에서는 구문이 해석되지 않습니다(Code 62).

**TTL** (`06`): `TTL snapshot_id + INTERVAL 3 HOUR`와 `ttl_only_drop_parts = 1`에서 시간별 스냅샷 6개가
`OPTIMIZE … FINAL` 뒤 3개(0, 1, 2시간 전)로 줄었습니다. 이전 스냅샷이 `raw`에서 지워진 상태에서 보호된 MV는
다음 스냅샷에 대해 아무것도 쓰지 않았습니다. 이전 쪽이 빈 같은 비교는 다음 스냅샷의 레코드를 모두 신규로
보고합니다(여기서는 10,000개).

#### 100만 · 1,000만 레코드

레코드 100만 개 스냅샷 하나는 `raw`에서 압축 170 MB(비압축 388 MB), 1,000만 개는 1.69 GB(3.96 GB)입니다.
실행은 세 번, 모두 2026-11-17(UTC)이고 로그와 JSON은 `results/`에 있습니다.

- **실행 1**(`scale-run-1.log`, 08:37–08:46): 8 GiB 레플리카 2개(사용 가능 6.85 GiB), `max_threads` 2. 1,000만에서
  JOIN 비교가 메모리를 넘긴 뒤 서비스가 확장되며 레플리카가 교체되어 멈췄습니다.
- **실행 2**(`scale-run-2.log`, `scale-26.8.1.654-run-2.json`, 08:48–09:02, `--lean`): 교체 중(기존 8 GiB와 새
  레플리카가 함께 있음). 1,000만에서 클라이언트 쪽 DNS 실패로 멈췄습니다.
- **실행 3**(`scale-run-3.log`, `scale-26.8.1.654-10m-resume.json`, 11:36–11:42, `--lean --resume`): 1,000만의
  나머지를 12 GiB 레플리카 2개(사용 가능 10.67 GiB), `max_threads` 3에서.

| 측정 | 레코드 100만 | 레코드 1,000만 |
|---|---|---|
| JOIN 비교(`03`), `row_hash` 열 | 1.65–5.29초 · 1.31 GiB(실행 1) | 실행 1: 두 번 모두 ✗ Code 241(서버가 6.85 GiB에 닿았을 때 쿼리 4.10–4.39 GiB). 실행 2: 8 GiB 레플리카에서 ✗ 241, 더 큰 레플리카에서 12.5초 · **6.73 GiB** |
| JOIN 비교, 조회 때 해시 계산 | 3.01–4.01초 · 1.13 GiB(실행 1) | ✗ Code 241(실행 1) |
| JOIN 비교, `LIMIT 1 BY` 없음 | 1.38–2.29초 · 1.31 GiB(실행 1) | ✗ Code 241(실행 1) |
| JOIN 비교, `full_sorting_merge`(anti join은 hash로) | 2.21–4.55초 · 1.50 GiB(실행 1) | ✗ Code 241(실행 1) |
| `GROUP BY` 분류, 키와 해시만 | 0.25–0.32초 · 275 MiB(실행 1) | 6.39–11.19초 · 2.47 GiB(실행 1). 2.3–3.5초 · 1.96 GiB(실행 2–3) |
| 두 단계 비교(분류한 뒤 바뀐 키만 행과 JOIN) | 1.17–1.33초 · 421–614 MiB(실행 2) | 11.1–18.6초 · **1.97 GiB**, 4회(실행 2–3) |
| 파티션 없는 `ORDER BY record_key` 테이블에서 두 단계 비교 | 1.20–1.22초 · 633 MiB(실행 2) | 10.3–18.3초 · 2.66 GiB(실행 3) |
| 가드: 스냅샷 하나의 `uniqExact(record_key)` | 0.09–0.10초 · 111 MiB | 1.12–1.49초 · 784 MiB(실행 1). 0.56–1.22초 · 1.02 GiB(실행 3) |
| 비교하는 갱신(`diff_rmv`, 두 단계) | 1.02초 · 602 MiB, 18,011행 씀(실행 2) | 12.18초 · 1.96 GiB, 180,101행 씀(실행 3) |
| 할 일이 없는 갱신 | 0.13초 · 3 MiB(실행 2) | 0.03초 · 3 MiB(실행 3) |
| 스냅샷의 10분의 1 INSERT, MV 없음 | 0.86–0.87초 | 3.65초 · 704 MiB(실행 3) |
| 같은 INSERT, INSERT 시점 MV 두 개(`05`) | 10분의 1마다 0.69–1.86초 · 355 MiB | 10분의 1마다 10.0–29.7초 · **5.07 GiB**(실행 3) |

갱신은 두 크기 모두 정답을 썼습니다(5,000 · 10,010 · 3,000, 50,000 · 100,100 · 30,000, 그리고 `'end'` 행).
INSERT 시점 MV는 같은 신규 · 변경 레코드를 찾았고 삭제는 찾지 못했습니다. 파티션이 있는 테이블과 없는 테이블의
읽은 행 수가 같았던 것은 비교하는 두 스냅샷만 들어 있었기 때문입니다. 파티션 없는 테이블은 보관하는 스냅샷이
늘수록 읽는 양이 늘어나며, 이는 재지 않았습니다.

### 이 실습이 확인하지 않은 것

- Kafka Connect Sink 자체: 스냅샷은 `INSERT … SELECT`로 만들고 재전달 배치는 흉내 냈습니다. 싱크의
  exactly-once 모드나 재시도가 배치를 어떻게 나누는지는 시험하지 않았습니다.
- `changes`를 주기적으로 읽는 것 말고 소비자에게 알리는 방법: Kafka 엔진 테이블, ClickPipes, 웹훅은 없습니다.
- 1,000만 레코드보다 큰 스냅샷, 레플리카당 8 GiB보다 큰 서비스.
