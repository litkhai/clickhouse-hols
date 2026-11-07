# SharedMergeTree internals, measured

[English](#english) | [한국어](#한국어)

## English

On ClickHouse Cloud, `ENGINE = MergeTree` becomes SharedMergeTree: parts live in object storage,
part metadata lives in Keeper, and replicas share both instead of copying parts to each other.
This lab measures what that means on a real service, from the system tables: what one INSERT
writes and where, what the other replica does when a part appears, who runs a merge, how soon
another replica sees a new row, what many small INSERTs cost with and without `async_insert`,
and which OSS DDL forms Cloud accepts.

**Verified on ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 2 replicas of 2 vCPU / 8 GiB),
2026-11-07, `run.sh 99` then `KEEP=1 run.sh` (steps `01` → `06`); `99` ran on its own the same day.
Every number below comes from that run, whose masked output is in [`runs/2026-11-07/`](runs/2026-11-07/);
a re-run will differ in the details.

Author: Ken Lee · MIT

### What each step shows

| Step | Writes | Shows |
|---|---|---|
| `01-setup.sql` | `smt_lab`, `smt_lab.big` | The Shared database engine; `MergeTree` stored as `SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`; the one-shard `default` cluster; `system.replicas` per replica; part-shaping MergeTree settings; insert consistency settings |
| `02-write-path.sql` | 2M rows into `big` | `NewPart` on the writer vs `DownloadPart` on the other replica, with object storage bytes; empty replication queue; Keeper requests of the INSERT, by Keeper node |
| `03-visibility.sh` | `smt_lab.vis` | 30 + 30 trials: INSERT one row, then ask both replicas at once; lag from `part_log`; cost of `select_sequential_consistency = 1`; `SYSTEM SYNC REPLICA … LIGHTWEIGHT` |
| `04-merges.sh` | `smt_lab.m` | 20 INSERTs, then every merge: on which replica it ran, and who only loaded the result |
| `05-small-inserts.sh` | `smt_lab.small_sync`, `small_async` | 200 one-row INSERTs from 20 clients, synchronous vs `async_insert = 1`: parts, object storage bytes, Keeper requests, latency |
| `06-ddl-port.sh` | `smt_lab.p*` | OSS DDL forms that fail (negative checks: the step fails if they succeed) and the forms that work; Distributed over `default` |
| `99-cleanup.sql` | drops `smt_lab` | — |

### Run

Needs the `clickhouse` binary (`clickhouse client`, and `clickhouse local` to redraw masked
tables) and a Cloud service with at least two replicas. The data is small (about 165 MiB); the
run takes a few minutes of compute and keeps the service awake while it runs.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh 99 && KEEP=1 ./run.sh           # clean start; every step but 99, objects kept for screenshots
./run.sh 99                              # drop the lab database when done
./run.sh 03                              # one step again (01 must have run)
```

Each shell step (`03`–`05`) reads only log rows written after it started, so it can be re-run on
its own. `02` reads rows since `01`, so re-run both together. Captures are masked unless `MASK=0`:
pod names keep only their random suffix (`2rdd723-0`), and the endpoint, namespace, bucket and
table UUIDs are replaced. `system.zookeeper` is not readable by the service's `default` user
(`ACCESS_DENIED`), so Keeper is observed through `system.aggregated_zookeeper_log` and the
`ZooKeeper*` profile events instead.

### What the 2026-11-07 run returned

**A plain CREATE TABLE.** The database engine is `Shared`; `ENGINE = MergeTree` is stored as
`SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`. The `default` cluster is one
shard with two replicas. `min_bytes_for_wide_part` is 1 GiB on this service, so every part in this
lab is Compact, even a 90 MiB one.

**One INSERT (step 02).** 2M rows became two parts (1,111,953 and 888,047 rows; 90 and 72 MiB). The
writer wrote 161.84 MiB to object storage; the query took 3.3 s and made 18 Keeper requests (16 of
them inside multi-requests). For each part the sink checks its replica node and that the
deduplication hash does not exist, then creates the hash, a block number, a `virtual_parts`
entry and an insert memo id, and sets the table and `virtual_parts` nodes.
The other replica logged a `DownloadPart` for each part (36 and 45 ms long). It read
**1.00 MiB in one GET for the 90 MiB part** and wrote nothing. Both replicas then reported the same
2 active parts and 161.84 MiB. `system.replication_queue` and `system.replicated_fetches` were
empty on both.

| Event | Replica | Part | Size | Object storage |
|---|---|---|---|---|
| NewPart | writer | all_0_0_0 | 89.98 MiB | 89.98 MiB written, 1,375 ms |
| DownloadPart | other | all_0_0_0 | 89.98 MiB | 1.00 MiB read (1 GET), 36 ms |
| NewPart | writer | all_1_1_0 | 71.86 MiB | 71.86 MiB written, 1,226 ms |
| DownloadPart | other | all_1_1_0 | 71.86 MiB | 1.00 MiB read (1 GET), 45 ms |

In step 04 the parts were small (about 170 KiB each), and each `DownloadPart` read about as many
bytes as the part held. The lab does not show *what* the 1 MiB read contains; it shows only that
the part data was not copied.

**Visibility across replicas (step 03).** Each trial INSERTs one row and asks both replicas
through `clusterAllReplicas` on the same connection; the check started 29–35 ms after the INSERT
finished (p50 31.5 ms).

| Check | Other replica saw the row at once |
|---|---|
| `select_sequential_consistency = 0` (default) | 29 of 30 |
| `select_sequential_consistency = 1` | 30 of 30 |

Server-side lag from `NewPart` on the writer to `DownloadPart` on the other replica, over 60
inserted parts: min 18.8 ms, p50 29.6 ms, p90 37.1 ms, max 77.4 ms. The lag and the check gap are
about the same size, which is why the default check missed a row now and then. (On two earlier
runs that day the default check saw 21 and 25 of 30, with the lag max at 385 ms on one run.)
On a plain `SELECT count()`, `select_sequential_consistency = 1` cost 2 Keeper requests and took
12.2 ms on average against 1 ms without it (10 runs each). `SYSTEM SYNC REPLICA smt_lab.vis
LIGHTWEIGHT` took 7–19 ms with 4 Keeper requests.

**Merges (step 04).** 20 INSERTs of 50,000 rows became 4 active parts after 3 merges. Each merge
ran on **one** replica, and the other logged one `DownloadPart` for its result:

| Merged part | Rows | From parts | Merged on | Loaded on the other replica |
|---|---|---|---|---|
| all_0_5_1 | 300,000 | 6 | 2rdd723-0 | 1 |
| all_0_10_2 | 550,000 | 6 | 2rdd723-0 | 1 |
| all_0_16_3 | 850,000 | 7 | 2rdd723-0 | 1 |

The merges wrote 5.70 MiB; the other replica wrote nothing for them. `system.replicas` named
6row3gp-0 as `merge_coordinator_replica` while the merges ran on 2rdd723-0, so the coordinator
is not necessarily the replica that merges. `queue_size` and `merges_in_queue` were 0 on both.

**Many small INSERTs (step 05).** 200 one-row INSERTs from 20 concurrent clients:

| | Parts created | Object storage written | Keeper requests | Client latency p50 / max |
|---|---|---|---|---|
| synchronous | 200 | 209.38 KiB | 1,210 | 85 / 118 ms |
| `async_insert = 1, wait_for_async_insert = 1` | 29 | 31.21 KiB | 194 (in the 29 flushes) | 834 / 1,089 ms |

With `async_insert` the server buffered 6.3–7.5 INSERTs per flush, and each flush is a query of
its own in `query_log`. The client waited for the flush (`async_insert_busy_timeout_max_ms` is
1000 on this service), so each INSERT took longer, while the service created a seventh of the parts
and made a sixth of the Keeper requests. The part-count limits (`parts_to_delay_insert` 1000, `parts_to_throw_insert`
3000, `max_parts_in_total` 10000) were not reached in this lab.

**Porting OSS DDL (step 06).**

| DDL | Result |
|---|---|
| `ON CLUSTER '{cluster}'` | fails, code 139: no `cluster` macro |
| `ReplicatedMergeTree('/clickhouse/tables/{shard}/t', '{replica}')` | fails, code 36: explicit Keeper path and replica name are not allowed in a Replicated database (unless `database_replicated_allow_replicated_engine_arguments` is set) |
| the same with `ON CLUSTER default` | fails, code 36 |
| `ReplicatedMergeTree` without arguments, with or without `ON CLUSTER default` | works → `SharedMergeTree` |
| `ReplicatedReplacingMergeTree(v)`, `AggregatingMergeTree` | work → `SharedReplacingMergeTree`, `SharedAggregatingMergeTree` |
| `Distributed(default, db, t, rand())` | works; one shard, so it returns each row once (1000 = 1000) |

### Not covered

- **Scale-out time** (adding a replica, or waking from idle) changes the service size and its bill,
  so it is not part of this run. Do it only on a service you own and may resize.
- **ReplicatedMergeTree side by side.** The comparison in the notes article uses the OSS
  behaviour documented in `core-architecture/oss-replicatedmergetree-distributed`; this lab has no
  OSS run.
- Reaching `parts_to_throw_insert`, Keeper load at high INSERT rates, and lightweight updates or
  deletes.

---

## 한국어

ClickHouse Cloud에서 `ENGINE = MergeTree`는 SharedMergeTree가 됩니다. 파트는 오브젝트 스토리지에,
파트 메타데이터는 Keeper에 있고, 레플리카는 파트를 서로 복사하지 않고 둘을 함께 씁니다. 이 실습은
실제 서비스의 system 테이블로 다음을 측정합니다. INSERT 하나가 무엇을 어디에 쓰는지, 파트가 생겼을 때
다른 레플리카가 무엇을 하는지, 병합은 누가 하는지, 다른 레플리카가 새 행을 얼마나 빨리 보는지, 작은
INSERT가 `async_insert` 유무에 따라 얼마나 드는지, OSS DDL 중 어떤 형태가 Cloud에서 통하는지.

**ClickHouse Cloud 26.8.1.608에서 검증** (AWS ap-northeast-2, 2 vCPU / 8 GiB 레플리카 2개),
2026-11-07, `run.sh 99` 후 `KEEP=1 run.sh`(단계 `01` → `06`). `99`는 같은 날 따로 실행했습니다.
아래 수치는 모두 이 실행에서 나온 값이며(마스킹한 출력은 [`runs/2026-11-07/`](runs/2026-11-07/)),
다시 실행하면 세부 값은 달라집니다.

작성: Ken Lee · MIT

### 단계별 내용

| 단계 | 쓰는 것 | 보여 주는 것 |
|---|---|---|
| `01-setup.sql` | `smt_lab`, `smt_lab.big` | Shared 데이터베이스 엔진, `SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`로 저장되는 `MergeTree`, 샤드 1개인 `default` 클러스터, 레플리카별 `system.replicas`, 파트 모양을 정하는 MergeTree 설정, INSERT 일관성 설정 |
| `02-write-path.sql` | `big`에 2M 행 | 쓴 레플리카의 `NewPart`와 다른 레플리카의 `DownloadPart`, 오브젝트 스토리지 바이트, 비어 있는 복제 큐, Keeper 노드별 INSERT 요청 |
| `03-visibility.sh` | `smt_lab.vis` | 30 + 30회: 한 행 INSERT 직후 두 레플리카에 동시에 묻기, `part_log` 기준 지연, `select_sequential_consistency = 1`의 비용, `SYSTEM SYNC REPLICA … LIGHTWEIGHT` |
| `04-merges.sh` | `smt_lab.m` | INSERT 20회 후 모든 병합: 어느 레플리카가 했고 누가 결과만 읽었는지 |
| `05-small-inserts.sh` | `smt_lab.small_sync`, `small_async` | 클라이언트 20개가 한 행 INSERT 200회, 동기 vs `async_insert = 1`: 파트 수, 오브젝트 스토리지 바이트, Keeper 요청, 지연 |
| `06-ddl-port.sh` | `smt_lab.p*` | 실패하는 OSS DDL(음성 검사: 성공하면 단계가 실패)과 통하는 형태, `default` 위의 Distributed |
| `99-cleanup.sql` | `smt_lab` 삭제 | — |

### 실행

`clickhouse` 바이너리(`clickhouse client`, 마스킹한 표를 다시 그리는 `clickhouse local`)와 레플리카가
2개 이상인 Cloud 서비스가 필요합니다. 데이터는 약 165 MiB로 작고, 몇 분의 컴퓨트를 쓰며, 실행 중에는
서비스가 아이들 상태로 들어가지 않습니다.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh 99 && KEEP=1 ./run.sh           # 깨끗하게 시작, 99를 뺀 모든 단계, 캡처용으로 객체 유지
./run.sh 99                              # 끝나면 실습 데이터베이스 삭제
./run.sh 03                              # 한 단계만 다시(01이 먼저 실행돼 있어야 함)
```

셸 단계(`03`–`05`)는 자기가 시작한 뒤의 로그 행만 읽으므로 따로 다시 실행해도 됩니다. `02`는 `01`
이후 행을 읽으니 둘을 함께 다시 실행합니다. 캡처는 `MASK=0`이 아니면 마스킹됩니다. 파드 이름은 끝의
무작위 부분(`2rdd723-0`)만 남기고, 엔드포인트·네임스페이스·버킷·테이블 UUID는 바꿉니다. 서비스의
`default` 사용자는 `system.zookeeper`를 읽을 수 없어서(`ACCESS_DENIED`), Keeper는
`system.aggregated_zookeeper_log`와 `ZooKeeper*` 프로파일 이벤트로 봅니다.

### 2026-11-07 실행 결과

**평범한 CREATE TABLE.** 데이터베이스 엔진은 `Shared`이고, `ENGINE = MergeTree`는
`SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`로 저장됩니다. `default` 클러스터는
샤드 1개, 레플리카 2개입니다. 이 서비스의 `min_bytes_for_wide_part`는 1 GiB여서, 90 MiB 파트까지
이 실습의 파트는 모두 Compact입니다.

**INSERT 하나(02단계).** 2M 행이 파트 2개(1,111,953행·888,047행, 90 MiB·72 MiB)가 되었습니다. 쓴
레플리카가 오브젝트 스토리지에 161.84 MiB를 썼고, 쿼리는 3.3초 걸렸으며 Keeper 요청은 18개(그중 16개는
multi 요청 안)였습니다. 파트마다 싱크는 자기 레플리카 노드와 중복 제거 해시가 없음을 확인하고, 해시·
블록 번호·`virtual_parts` 항목·insert memo id를 만들고, 테이블 노드와 `virtual_parts` 노드를 갱신합니다.
다른 레플리카는 파트마다 `DownloadPart`(36 ms, 45 ms)를 남겼습니다. **90 MiB 파트에 대해 GET
한 번으로 1.00 MiB를 읽었고** 쓴 것은 없습니다. 이후 두 레플리카 모두 활성 파트 2개, 161.84 MiB로 같게
보고했습니다. `system.replication_queue`와 `system.replicated_fetches`는 둘 다 비어 있었습니다.

| 이벤트 | 레플리카 | 파트 | 크기 | 오브젝트 스토리지 |
|---|---|---|---|---|
| NewPart | 쓴 쪽 | all_0_0_0 | 89.98 MiB | 89.98 MiB 쓰기, 1,375 ms |
| DownloadPart | 다른 쪽 | all_0_0_0 | 89.98 MiB | 1.00 MiB 읽기(GET 1회), 36 ms |
| NewPart | 쓴 쪽 | all_1_1_0 | 71.86 MiB | 71.86 MiB 쓰기, 1,226 ms |
| DownloadPart | 다른 쪽 | all_1_1_0 | 71.86 MiB | 1.00 MiB 읽기(GET 1회), 45 ms |

04단계의 파트는 작아서(각 약 170 KiB) `DownloadPart`가 파트 크기만큼을 읽었습니다. 이 실습은 1 MiB
읽기에 *무엇이* 들었는지는 보여 주지 않습니다. 파트 데이터가 복사되지 않았다는 것만 보여 줍니다.

**레플리카 간 가시성(03단계).** 매 시도는 한 행을 INSERT하고 같은 연결에서 `clusterAllReplicas`로 두
레플리카에 묻습니다. 확인 쿼리는 INSERT가 끝나고 29–35 ms 뒤에 시작했습니다(p50 31.5 ms).

| 확인 | 다른 레플리카가 바로 본 횟수 |
|---|---|
| `select_sequential_consistency = 0`(기본) | 30회 중 29회 |
| `select_sequential_consistency = 1` | 30회 중 30회 |

쓴 레플리카의 `NewPart`부터 다른 레플리카의 `DownloadPart`까지 서버 측 지연(INSERT 파트 60개): 최소
18.8 ms, p50 29.6 ms, p90 37.1 ms, 최대 77.4 ms. 지연과 확인 간격이 비슷한 크기라서 기본 설정의 확인이
가끔 행을 놓쳤습니다. (같은 날 앞선 두 번의 실행에서는 기본 확인이 30회 중 21회와 25회를 보았고, 한
번은 지연 최대가 385 ms였습니다.) 평범한 `SELECT count()`에서 `select_sequential_consistency = 1`은
Keeper 요청 2개가 더 들고 평균 12.2 ms 걸렸습니다(끄면 1 ms, 각 10회). `SYSTEM SYNC REPLICA smt_lab.vis
LIGHTWEIGHT`는 Keeper 요청 4개로 7–19 ms 걸렸습니다.

**병합(04단계).** 50,000행 INSERT 20회가 병합 3번 뒤 활성 파트 4개가 되었습니다. 병합은 모두 **한**
레플리카에서만 돌았고, 다른 레플리카는 결과마다 `DownloadPart`를 하나씩 남겼습니다.

| 병합된 파트 | 행 | 원본 파트 수 | 병합한 레플리카 | 다른 레플리카의 읽기 |
|---|---|---|---|---|
| all_0_5_1 | 300,000 | 6 | 2rdd723-0 | 1 |
| all_0_10_2 | 550,000 | 6 | 2rdd723-0 | 1 |
| all_0_16_3 | 850,000 | 7 | 2rdd723-0 | 1 |

병합은 5.70 MiB를 썼고, 다른 레플리카는 이 병합으로 아무것도 쓰지 않았습니다. `system.replicas`의
`merge_coordinator_replica`는 6row3gp-0였지만 병합은 2rdd723-0에서 돌았습니다. 코디네이터가 곧 병합하는
레플리카는 아닙니다. 두 레플리카 모두 `queue_size`와 `merges_in_queue`는 0이었습니다.

**작은 INSERT 여러 개(05단계).** 동시 클라이언트 20개가 한 행 INSERT 200회:

| | 생긴 파트 | 오브젝트 스토리지 쓰기 | Keeper 요청 | 클라이언트 지연 p50 / 최대 |
|---|---|---|---|---|
| 동기 | 200 | 209.38 KiB | 1,210 | 85 / 118 ms |
| `async_insert = 1, wait_for_async_insert = 1` | 29 | 31.21 KiB | 194(플러시 29회 안) | 834 / 1,089 ms |

`async_insert`에서는 서버가 플러시 한 번에 INSERT 6.3–7.5개를 모았고, 플러시는 `query_log`에 별도 쿼리로
남습니다. 클라이언트는 플러시를 기다렸으므로(이 서비스의 `async_insert_busy_timeout_max_ms`는 1000)
INSERT 하나하나는 느려졌지만, 서비스가 만든 파트는 약 7분의 1, Keeper 요청은 약 6분의 1이었습니다. 파트 수 한도
(`parts_to_delay_insert` 1000, `parts_to_throw_insert` 3000, `max_parts_in_total` 10000)에는 이
실습에서 닿지 않았습니다.

**OSS DDL 옮기기(06단계).**

| DDL | 결과 |
|---|---|
| `ON CLUSTER '{cluster}'` | 실패, 코드 139: `cluster` 매크로가 없음 |
| `ReplicatedMergeTree('/clickhouse/tables/{shard}/t', '{replica}')` | 실패, 코드 36: Replicated 데이터베이스에서는 Keeper 경로와 레플리카 이름을 명시할 수 없음(`database_replicated_allow_replicated_engine_arguments`를 켜지 않는 한) |
| 같은 문장에 `ON CLUSTER default` | 실패, 코드 36 |
| 인자 없는 `ReplicatedMergeTree`, `ON CLUSTER default` 유무와 무관 | 통함 → `SharedMergeTree` |
| `ReplicatedReplacingMergeTree(v)`, `AggregatingMergeTree` | 통함 → `SharedReplacingMergeTree`, `SharedAggregatingMergeTree` |
| `Distributed(default, db, t, rand())` | 통함. 샤드가 1개라 각 행을 한 번만 돌려줌(1000 = 1000) |

### 다루지 않은 것

- **스케일아웃 시간**(레플리카 추가, 아이들에서 깨우기)은 서비스 크기와 비용을 바꾸므로 이 실행에 넣지
  않았습니다. 크기를 바꿔도 되는 자기 서비스에서만 하세요.
- **ReplicatedMergeTree와 나란히 비교.** 노트 글의 비교는 `core-architecture/oss-replicatedmergetree-distributed`에
  정리된 OSS 동작을 씁니다. 이 실습에는 OSS 실행이 없습니다.
- `parts_to_throw_insert` 도달, 높은 INSERT 속도에서의 Keeper 부하, lightweight update·delete.
