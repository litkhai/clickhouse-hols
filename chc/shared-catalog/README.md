# Shared Catalog on ClickHouse Cloud: DDL, lifecycle, propagation

[English](#english) | [한국어](#한국어)

## English

On ClickHouse Cloud every database is a `Shared` database: the definition of every object
lives in one versioned state in Keeper, and replicas hold only an in-memory copy. This lab
runs the DDL that shows what that changes — engine choice, CTAS, cross-database `RENAME`,
`DROP`/`UNDROP`, `ON CLUSTER`, table engines — and measures what the docs leave open: how
fast a DDL reaches the other replica, what concurrent DDL does, whether a bigger catalog
slows DDL down, and whether an idle service in the same warehouse blocks database DDL.
The evidence is the catalog's own log: every replica writes each state change it applies to
`system.text_log` (logger `SharedDatabaseCatalog`), with the global version and the object's
stage.

`oss/` is the comparison on open-source ClickHouse (Docker): where Atomic, `ON CLUSTER` and
the `Replicated` database engine keep the catalog, read from the real Keeper tree.

**Verified on ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 2 replicas, fast release
channel; the warehouse also has a read-only service with 1 replica, idle throughout),
2026-11-07, full run `01` → `99` in 487 s. Other workloads ran on the service at the same
time (848 catalog versions in the 30 minutes before the lab started).

Author: Ken Lee · MIT

### What each step shows

| Step | Writes | Shows |
|---|---|---|
| `01-inventory.sh` | — | Version and replicas, the `default` and `all_groups.default` clusters, database engines, catalog metrics per replica, DDL settings, `system.zookeeper` access, the catalog log by message shape and versions per 30 minutes |
| `02-ddl.sh` | `sc_lab`, `sc_lab2` | `CREATE DATABASE` with an engine, CTAS failure and success, a CTAS in flight, cross-database `RENAME`/`EXCHANGE`, `RENAME DATABASE`, `DETACH`, `ON CLUSTER` (`default`, `all_groups.default`, unknown), `ALTER`, table engines and what they become, Memory/Set/Join data per replica |
| `03-lifecycle.sh` | `sc_lab_dropdb` | One table from CREATE to final removal as the replicas log it, the object JSON, `UNDROP`, retention 0 by query `SETTINGS` and by session, `DROP … SYNC`, `DROP DATABASE` |
| `04-propagation.sh` | `sc_lab.p*` | 10 rounds of CREATE/ALTER/RENAME/DROP: commit on one replica → applied on the other, and the time the client waits |
| `05-concurrency.sh` | `sc_lab.cc_*` | 8 parallel `ALTER` on one table vs on 8 tables |
| `06-scale.sh` | `sc_scale` (800 tables) | CREATE and state-application time before and after adding 800 tables, `DROP DATABASE … SYNC` of 800 tables |
| `07-warehouse.sh` | `sc_wh*` | `CREATE`/`RENAME`/`DROP DATABASE` while the other service of the warehouse is idle, in three output modes; service states from the Cloud API |
| `08-objects.sh` | `sc_lab.dict*`, `sc_lab.rmv` | A dictionary (who loads it) and a refreshable MV (who refreshes, what a refresh does to the catalog) |
| `99-cleanup.sql` | drops `sc_*` | — |

### Run

Needs the `clickhouse` binary (`clickhouse client`, and `clickhouse local` to redraw masked
tables) and a Cloud service with at least two replicas. Step `06` creates 800 empty tables
and drops them; nothing else stores more than 5M rows. Step `07` reads service states only
if a Cloud API key is set (read-only, `CHC_KEY` / `CHC_SECRET`); it never connects to the
idle service.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh               # every step; output also goes to out/ (gitignored)
./run.sh 04 05         # only some steps (02 must have run first: it creates sc_lab)
SCALE_N=200 ./run.sh 06
```

Each statement opens its own connection, so consecutive statements can land on different
replicas, as with an HTTP client or a pool. Output is masked unless `MASK=0` (pod names keep
only their suffix, the endpoint and Keeper host names are replaced). The masked log of the
verified run is `runs/2026-11-07.txt`.

### What the 2026-11-07 run returned

Numbers are from the verified run (02:00–02:08 UTC). Two earlier runs the same day
(01:39 and 01:52 UTC, while the steps were being written) are mentioned only where they differed.

**Where the catalog is**
- 23 `Shared` databases, `system` stays `Atomic`, `INFORMATION_SCHEMA` is `Memory`. Both
  clusters (`default` with 2 replicas, `all_groups.default` with the idle service's replica
  as well) have `is_shared_catalog_cluster = 1`.
- `system.zookeeper` is denied for every path, `/` included (`ACCESS_DENIED`, Code 497), while
  `system.zookeeper_connection` is readable: the Keeper tree cannot be read on Cloud, so the
  evidence here is the catalog's log.
- In the 30 minutes before the lab, one replica's log went through 848 global versions and
  applied 466 states, median 10.3 ms each: replicas skip intermediate versions and apply the
  latest. A state fetch reads only changed objects ("UUIDs size 288, fetched 1 (cached 287)",
  ZK query median 2 ms).

**Lifecycle, as the replicas log it** (`03`)
- The catalog stores each object as JSON: `create_query`, `stage` (1 = CREATED, 3 =
  DROP_SCHEDULED), `type`, and when dropped `next_drop_attempt_timestamp` and
  `temporary_name` (`<database uuid>|<name>`). Every DDL bumps the object's version: CREATE v1,
  ALTER v2, RENAME v3, DROP v4, UNDROP v5.
- The replica that runs a DDL logs the commit ("… at global version N"); the other replica logs
  "Applying changes for object … from stage X version n to stage Y version n+1".
- `DROP` → `DROP_SCHEDULED`, `system.dropped_tables` shows the removal time (DROP + 8 h),
  `UNDROP` brings back the same UUID and its 1,000 rows. The drop thread logs the applied version
  of each active replica and "Discarded inactive replicas" for the idle service's replica: an
  idle replica does not hold up the final removal.
- Retention 0: on 26.8 the **query-level** `DROP … SETTINGS database_shared_drop_table_delay_seconds = 0`
  is applied (removal time = DROP time), as is the session setting. On Cloud 26.6
  (2026-10-13, by hand) the query-level form was not applied. Retention 0 makes the object
  eligible at once, but the removal waits for the drop thread: `UNDROP` 20 s later succeeded in
  the 01:52 and 02:01 runs, and failed (`UNKNOWN_TABLE`, removal 8 s after DROP) in the 01:39 run.
- `DROP … SYNC` → `UNDROP` fails with `UNKNOWN_TABLE`.
- `DROP DATABASE` (no `SYNC`) removes its tables at once: the log shows "Will try to reset
  delay to drop table … to 0", the table goes DROP_SCHEDULED → DROP_IN_PROGRESS → removed in
  about 1.3 s, and nothing appears in `system.dropped_tables`. `UNDROP DATABASE` does not exist
  (Code 62 syntax error); `UNDROP TABLE` in the dropped database fails with `UNKNOWN_DATABASE`.

**DDL matrix** (`02`, same results in all three runs)
- `CREATE DATABASE … ENGINE = Atomic` and `= Replicated(…)`: Code 344 ("Only queries like
  `CREATE DATABASE <database>` are supported").
- CTAS failing at row 3,000,000 of 5,000,000: no table on either replica. While a 6 s CTAS was
  running, the table did not exist on either replica (`SELECT` → `UNKNOWN_TABLE`); it appeared
  on both when the statement returned.
- Cross-database `RENAME` keeps the UUID, `EXCHANGE TABLES` across databases works,
  `RENAME DATABASE` keeps the database UUID (the other replica renames through a temporary
  name `_renamed_<old>_<new>`).
- Plain `DETACH TABLE`: Code 80. `DETACH … PERMANENTLY` lists the table in
  `system.detached_tables` on both replicas, with `is_permanently` 1 on one replica and 0 on
  the other; `ATTACH TABLE` brings it back on both.
- `ON CLUSTER default`: the clause is dropped. `ON CLUSTER 'all_groups.default'`: a
  `distributed_ddl_queue` entry, both replicas refuse it ("It's not initial query. ON CLUSTER
  is not allowed for Shared Catalog", Code 80), the idle replica's row stays `Inactive`, no
  table. Unknown cluster: Code 701.
- Engines: Log, TinyLog, StripeLog, EmbeddedRocksDB → Code 36 ("must use engines that do not
  store data on disk"). `ReplicatedMergeTree` → `SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`;
  with a literal replica name → Code 80; with `{shard}`/`{replica}` macros → Code 36 (needs
  `database_replicated_allow_replicated_engine_arguments`). `Set`/`Join` → `SharedSet`/`SharedJoin`
  (inner `SharedReplacingMergeTree`), 100 rows on both replicas. `Memory`: 100 rows on the
  replica that took the INSERT, 0 on the other.

**Propagation** (`04`, 10 rounds of CREATE/ALTER/RENAME/DROP SYNC, 40 DDLs, 22/18 per replica)

| DDL | commit → applied on the other replica, p50 / p90 / max | server time, client statement p50 | of which waiting for replicas, p50 |
|---|---|---|---|
| CREATE | 23.2 / 45.5 / 47.8 ms | 159 ms | 87.5 ms |
| ALTER ADD COLUMN | 13.1 / 15.3 / 19.6 ms | 75.5 ms | 68 ms |
| RENAME | 8.9 / 16.7 / 22.8 ms | 30.5 ms | 17 ms |
| DROP … SYNC | 32.5 / 43.1 / 89.2 ms | 1,348.5 ms | 1,015 ms |

Each DDL appears twice in `query_log` with the same `log_comment`: the statement the client
sent and the one the catalog rewrites (UUID filled in) and runs inside it; the difference is the
wait for the other replicas under `none_only_active`.

**Concurrency** (`05`): 8 parallel `ALTER … ADD COLUMN` on one table → 3 succeeded, 5 failed with
Code 517 `CANNOT_ASSIGN_ALTER` ("Previous mutation query is not finished yet … You can retry
this error"); both replicas ended with the same 3 new columns. 8 parallel ALTERs on 8 tables →
8 succeeded (p50 56.5 ms). (Earlier runs: 3/5 and 4/4.)

**Catalog size** (`06`): 20 CREATE TABLE with 297 objects in the state: p50 160 ms; after adding
800 empty tables (1,100 objects): p50 152 ms. State application on the other replica stayed at
p50 9–10 ms. Creating the 800 tables over one connection took 138 s; `DROP DATABASE … SYNC`
of them, 78 s.

**Warehouse with an idle service** (`07`): `CREATE DATABASE`, `CREATE TABLE`, `RENAME DATABASE`,
`DROP DATABASE` returned in 0.21–0.36 s (server 5–172 ms) with the default
`none_only_active`, with `throw` and a 20 s timeout, and with timeout 0. The Cloud API showed
the read-only service `idle` before and after. The Warehouses docs' warning that these could be
blocked by idle services did not reproduce on 26.8.

**Objects with per-replica work** (`08`): a `HASHED` dictionary was loaded on both replicas at
CREATE (1,000 elements each). A refreshable MV every 10 s refreshed on one replica at a time
(`last_refresh_replica` the same on both; 3 refreshes on each replica in 45 s). Each refresh is
three catalog DDLs: `CREATE OR REPLACE TABLE … .tmp.inner_id.…` (itself a rename from
`_tmp_replace_…`), `EXCHANGE TABLES` with the inner table, `DROP TABLE` of the old one, each
with its own version and stages on both replicas.

**OSS comparison** (`oss/`, 26.8.36.3): see `oss/README.md` — the real Keeper trees of a
ReplicatedMergeTree table, a `task_queue/ddl` entry and a `Replicated` database; the
Replicated database's errors; CTAS blocked only for replicated target engines; recovery of a
lagging replica into `<db>_broken_tables`.

**Not measured:** a new replica joining (scale-out or resume from idle) — it needs a service
size change, i.e. spend, and was left for the owner to approve. Console captures were not
taken (they would mean entering the service password into a page).

---

## 한국어

ClickHouse Cloud의 데이터베이스는 모두 `Shared` 데이터베이스입니다. 모든 객체의 정의가 Keeper의
버전 붙은 상태 하나에 있고, 레플리카는 메모리 사본만 가집니다. 이 실습은 그 차이를 보여 주는 DDL
(엔진 지정, CTAS, 데이터베이스 간 `RENAME`, `DROP`/`UNDROP`, `ON CLUSTER`, 테이블 엔진)을 돌리고,
문서가 비워 둔 것을 잽니다. DDL이 다른 레플리카에 닿는 시간, 동시 DDL의 결과, 카탈로그가 커지면
DDL이 느려지는지, 같은 warehouse의 idle 서비스가 데이터베이스 DDL을 막는지입니다. 근거는 카탈로그
자신의 로그입니다. 레플리카마다 적용한 상태 변경을 전역 버전·객체 단계와 함께
`system.text_log`(logger `SharedDatabaseCatalog`)에 남깁니다.

`oss/`는 오픈소스 ClickHouse(Docker) 비교입니다. Atomic, `ON CLUSTER`, `Replicated` 데이터베이스
엔진이 카탈로그를 어디에 두는지 실제 Keeper 트리로 봅니다.

**검증: ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 레플리카 2대, fast 릴리스 채널.
같은 warehouse에 레플리카 1대짜리 읽기 전용 서비스가 있고 내내 idle), 2026-11-07,
`01` → `99` 전체 실행 487초. 같은 시간 서비스에는 다른 워크로드도 돌았습니다(실습 시작 전 30분
동안 카탈로그 버전 848개).

작성: Ken Lee · MIT

### 단계별 내용

| 단계 | 쓰기 | 보여 주는 것 |
|---|---|---|
| `01-inventory.sh` | — | 버전과 레플리카, `default`·`all_groups.default` 클러스터, 데이터베이스 엔진, 레플리카별 카탈로그 지표, DDL 설정, `system.zookeeper` 권한, 메시지 형태별 카탈로그 로그와 30분 동안의 버전 수 |
| `02-ddl.sh` | `sc_lab`, `sc_lab2` | 엔진을 지정한 `CREATE DATABASE`, CTAS 실패·성공, 실행 중인 CTAS, 데이터베이스 간 `RENAME`/`EXCHANGE`, `RENAME DATABASE`, `DETACH`, `ON CLUSTER`(`default`, `all_groups.default`, 없는 이름), `ALTER`, 테이블 엔진과 바뀌는 결과, Memory/Set/Join의 레플리카별 데이터 |
| `03-lifecycle.sh` | `sc_lab_dropdb` | 테이블 하나의 CREATE부터 최종 삭제까지 레플리카 로그, 객체 JSON, `UNDROP`, 쿼리 `SETTINGS`와 세션 설정의 보존 0, `DROP … SYNC`, `DROP DATABASE` |
| `04-propagation.sh` | `sc_lab.p*` | CREATE/ALTER/RENAME/DROP 10회: 한 레플리카의 커밋 → 다른 레플리카 적용, 클라이언트가 기다리는 시간 |
| `05-concurrency.sh` | `sc_lab.cc_*` | 한 테이블에 동시 `ALTER` 8개 대 테이블 8개에 하나씩 |
| `06-scale.sh` | `sc_scale`(테이블 800개) | 테이블 800개를 더하기 전후의 CREATE 시간과 상태 적용 시간, 800개 테이블의 `DROP DATABASE … SYNC` |
| `07-warehouse.sh` | `sc_wh*` | warehouse의 다른 서비스가 idle일 때 `CREATE`/`RENAME`/`DROP DATABASE`, 출력 모드 세 가지, Cloud API로 본 서비스 상태 |
| `08-objects.sh` | `sc_lab.dict*`, `sc_lab.rmv` | 딕셔너리(누가 적재하나), refreshable MV(누가 refresh하나, refresh가 카탈로그에 하는 일) |
| `99-cleanup.sql` | `sc_*` 삭제 | — |

### 실행

`clickhouse` 바이너리(`clickhouse client`, 가린 표를 다시 그리는 `clickhouse local`)와 레플리카가
2대 이상인 Cloud 서비스가 필요합니다. `06`은 빈 테이블 800개를 만들고 지웁니다. 그 밖에는
500만 행을 넘는 데이터가 없습니다. `07`은 Cloud API 키(`CHC_KEY` / `CHC_SECRET`, 읽기만)가 있을
때만 서비스 상태를 읽고, idle 서비스에는 접속하지 않습니다.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh               # 모든 단계, 출력은 out/에도 (gitignore)
./run.sh 04 05         # 일부 단계만 (02가 sc_lab을 만들므로 먼저 실행)
SCALE_N=200 ./run.sh 06
```

문장마다 새 연결을 엽니다. HTTP 클라이언트나 커넥션 풀처럼 이어지는 문장이 다른 레플리카로 갈 수
있습니다. 출력은 `MASK=0`이 아니면 가립니다(파드 이름은 끝 접미사만, 엔드포인트와 Keeper 호스트
이름은 바꿈). 검증한 실행의 로그는 `runs/2026-11-07.txt`입니다.

### 2026-11-07 실행 결과

수치는 검증한 실행(02:00–02:08 UTC)의 것입니다. 같은 날 단계를 쓰면서 돌린 두 번(01:39, 01:52
UTC)은 결과가 달랐을 때만 적습니다.

**카탈로그의 위치**
- `Shared` 데이터베이스 23개, `system`은 `Atomic`, `INFORMATION_SCHEMA`는 `Memory`. 두 클러스터
  (`default`는 레플리카 2대, `all_groups.default`는 idle 서비스의 레플리카까지) 모두
  `is_shared_catalog_cluster = 1`.
- `system.zookeeper`는 `/`를 포함해 모든 경로가 거부(`ACCESS_DENIED`, Code 497)되고
  `system.zookeeper_connection`은 읽힙니다. Cloud에서는 Keeper 트리를 읽을 수 없으므로 여기서는
  카탈로그 로그가 근거입니다.
- 실습 전 30분 동안 한 레플리카의 로그에서 전역 버전은 848개 지나갔고, 적용한 상태는 466번(중앙값
  10.3 ms)이었습니다. 레플리카는 중간 버전을 건너뛰고 최신 상태를 적용합니다. 상태를 가져올 때는
  바뀐 객체만 읽습니다("UUIDs size 288, fetched 1 (cached 287)", ZK 조회 중앙값 2 ms).

**레플리카 로그로 본 생명주기** (`03`)
- 카탈로그는 객체를 JSON으로 저장합니다. `create_query`, `stage`(1 = CREATED, 3 = DROP_SCHEDULED),
  `type`, 지운 뒤에는 `next_drop_attempt_timestamp`와 `temporary_name`(`<데이터베이스 uuid>|<이름>`).
  DDL마다 객체 버전이 오릅니다: CREATE v1, ALTER v2, RENAME v3, DROP v4, UNDROP v5.
- DDL을 실행한 레플리카는 커밋("… at global version N")을, 다른 레플리카는 "Applying changes for
  object … from stage X version n to stage Y version n+1"을 남깁니다.
- `DROP` → `DROP_SCHEDULED`. `system.dropped_tables`의 삭제 시각은 DROP + 8시간이고, `UNDROP`은
  같은 UUID와 1,000행을 되돌립니다. drop 스레드는 활성 레플리카마다 적용 버전을 기록하고, idle
  서비스의 레플리카는 "Discarded inactive replicas"로 뺍니다. idle 레플리카가 최종 삭제를 붙잡지
  않습니다.
- 보존 0: 26.8에서는 **쿼리 수준** `DROP … SETTINGS database_shared_drop_table_delay_seconds = 0`도
  적용됩니다(삭제 시각 = DROP 시각). 세션 설정도 마찬가지입니다. Cloud 26.6(2026-10-13, 수동
  실행)에서는 쿼리 수준이 적용되지 않았습니다. 보존 0은 객체를 곧바로 삭제 대상으로 만들 뿐이고,
  실제 삭제는 drop 스레드를 기다립니다. 20초 뒤 `UNDROP`이 01:52·02:01 실행에서는 성공했고, 01:39
  실행에서는 실패했습니다(`UNKNOWN_TABLE`, DROP 8초 뒤 삭제).
- `DROP … SYNC` 뒤 `UNDROP`은 `UNKNOWN_TABLE`.
- `DROP DATABASE`(`SYNC` 없이)는 안의 테이블을 바로 지웁니다. 로그에 "Will try to reset delay to
  drop table … to 0"이 남고, 테이블은 약 1.3초 만에 DROP_SCHEDULED → DROP_IN_PROGRESS → 삭제로
  가며 `system.dropped_tables`에 나오지 않습니다. `UNDROP DATABASE`는 없고(Code 62 구문 오류),
  지운 데이터베이스의 `UNDROP TABLE`은 `UNKNOWN_DATABASE`.

**DDL 표** (`02`, 세 번 모두 같은 결과)
- `CREATE DATABASE … ENGINE = Atomic`과 `= Replicated(…)`: Code 344("Only queries like
  `CREATE DATABASE <database>` are supported").
- 500만 행 중 300만 번째에서 실패한 CTAS: 어느 레플리카에도 테이블 없음. 6초짜리 CTAS가 도는 동안에도
  테이블은 어느 레플리카에도 없었고(`SELECT` → `UNKNOWN_TABLE`), 문장이 끝날 때 두 레플리카에
  나타났습니다.
- 데이터베이스 간 `RENAME`은 UUID를 유지하고, 데이터베이스 간 `EXCHANGE TABLES`도 됩니다.
  `RENAME DATABASE`는 데이터베이스 UUID를 유지합니다(다른 레플리카는 임시 이름
  `_renamed_<old>_<new>`를 거쳐 바꿈).
- 그냥 `DETACH TABLE`: Code 80. `DETACH … PERMANENTLY`는 두 레플리카의 `system.detached_tables`에
  나오는데 `is_permanently`가 한쪽은 1, 다른 쪽은 0. `ATTACH TABLE`로 두 레플리카에 돌아옵니다.
- `ON CLUSTER default`: 절이 지워짐. `ON CLUSTER 'all_groups.default'`: `distributed_ddl_queue` 항목이
  생기고 두 레플리카가 거부("It's not initial query. ON CLUSTER is not allowed for Shared Catalog",
  Code 80), idle 레플리카 행은 `Inactive`, 테이블 없음. 없는 클러스터: Code 701.
- 엔진: Log, TinyLog, StripeLog, EmbeddedRocksDB → Code 36("must use engines that do not store data on
  disk"). `ReplicatedMergeTree` → `SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`,
  replica 이름을 문자로 주면 Code 80, `{shard}`/`{replica}` 매크로로 주면 Code 36
  (`database_replicated_allow_replicated_engine_arguments` 필요). `Set`/`Join` → `SharedSet`/`SharedJoin`
  (안쪽은 `SharedReplacingMergeTree`), 두 레플리카에 100행. `Memory`: INSERT를 받은 레플리카에 100행,
  다른 쪽 0행.

**전파** (`04`, CREATE/ALTER/RENAME/DROP SYNC 10회, DDL 40개, 레플리카별 22/18개)

| DDL | 커밋 → 다른 레플리카 적용, p50 / p90 / 최대 | 서버 시간, 클라이언트 문장 p50 | 그중 레플리카 대기, p50 |
|---|---|---|---|
| CREATE | 23.2 / 45.5 / 47.8 ms | 159 ms | 87.5 ms |
| ALTER ADD COLUMN | 13.1 / 15.3 / 19.6 ms | 75.5 ms | 68 ms |
| RENAME | 8.9 / 16.7 / 22.8 ms | 30.5 ms | 17 ms |
| DROP … SYNC | 32.5 / 43.1 / 89.2 ms | 1,348.5 ms | 1,015 ms |

DDL 하나가 `query_log`에 같은 `log_comment`로 두 번 남습니다. 클라이언트가 보낸 문장과, 카탈로그가
UUID를 채워 그 안에서 실행하는 문장입니다. 차이가 `none_only_active`에서 다른 레플리카를 기다린
시간입니다.

**동시성** (`05`): 한 테이블에 `ALTER … ADD COLUMN` 8개를 동시에 → 3개 성공, 5개는 Code 517
`CANNOT_ASSIGN_ALTER`("Previous mutation query is not finished yet … You can retry this error"),
두 레플리카 모두 같은 새 컬럼 3개. 테이블 8개에 하나씩 → 8개 모두 성공(p50 56.5 ms).
(앞선 실행: 3/5, 4/4.)

**카탈로그 크기** (`06`): 상태의 객체 297개일 때 CREATE TABLE 20번 p50 160 ms, 빈 테이블 800개를
더한 뒤(객체 1,100개) p50 152 ms. 다른 레플리카의 상태 적용은 p50 9–10 ms 그대로. 테이블 800개를
한 연결로 만드는 데 138초, 그 데이터베이스의 `DROP DATABASE … SYNC`는 78초.

**idle 서비스가 있는 warehouse** (`07`): `CREATE DATABASE`, `CREATE TABLE`, `RENAME DATABASE`,
`DROP DATABASE`가 기본 `none_only_active`, `throw`+시간 제한 20초, 시간 제한 0 모두에서 0.21–0.36초
(서버 5–172 ms)에 끝났습니다. Cloud API에서 읽기 전용 서비스는 전후 모두 `idle`. idle 서비스가 이
DDL을 막을 수 있다는 Warehouses 문서의 주의는 26.8에서 재현되지 않았습니다.

**레플리카별로 일하는 객체** (`08`): `HASHED` 딕셔너리는 CREATE 때 두 레플리카가 각각 적재
(1,000개씩). 10초마다 도는 refreshable MV는 한 번에 한 레플리카에서만 refresh(`last_refresh_replica`가
두 레플리카에서 같음, 45초 동안 레플리카마다 3번). refresh 한 번은 카탈로그 DDL 세 개입니다.
`CREATE OR REPLACE TABLE … .tmp.inner_id.…`(그 자체가 `_tmp_replace_…`의 RENAME), 안쪽 테이블과의
`EXCHANGE TABLES`, 옛 테이블 `DROP TABLE`. 각각 두 레플리카에 버전과 단계가 남습니다.

**OSS 비교** (`oss/`, 26.8.36.3): `oss/README.md` — ReplicatedMergeTree 테이블, `task_queue/ddl` 항목,
`Replicated` 데이터베이스의 실제 Keeper 트리, Replicated 데이터베이스의 오류, 복제 엔진 대상에만
막히는 CTAS, 뒤처진 레플리카가 `<db>_broken_tables`로 복구되는 과정.

**재지 않은 것:** 새 레플리카 합류(확장 또는 idle에서 재개). 서비스 크기를 바꿔야 해서(비용) 소유자
승인 대상으로 남겼습니다. 콘솔 캡처는 찍지 않았습니다(서비스 비밀번호를 페이지에 넣어야 함).
