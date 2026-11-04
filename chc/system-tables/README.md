# ClickHouse Cloud system tables in depth

[English](#english) | [한국어](#한국어)

## English

A ClickHouse Cloud service is several replicas behind one endpoint, and most of the `system`
database describes only the replica that answers. This lab shows which tables are per replica
and which are shared, where the log tables are stored, how log history survives a replica being
replaced, and the query patterns that read all of it: `clusterAllReplicas`, `merge()`,
`KILL QUERY ON CLUSTER`. A small workload of its own (5M rows, a materialized view, a mutation,
a failing query, a long query that gets killed) gives every log table something to show.

**Verified on ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 2 replicas of 2 vCPU / 8 GiB,
fast release channel), 2026-11-04, full run `01` → `99` in 58 s. `oss-diff.sh` compared it with
`clickhouse/clickhouse-server:26.8` (26.8.36.3).

Author: Ken Lee · MIT

### What each step shows

| Step | Writes | Shows |
|---|---|---|
| `01-inventory.sql` | — | Kinds of system table (in-memory, log, older log generations); log tables with size and TTL; the object-storage policy and disks they live on; Cloud-only tables; logging settings |
| `02-replicas.sql`, `02-routing.sh` | — | The replicas behind the endpoint, the `default` and `all_groups.default` clusters, `query_log` counted per replica, ten connections spread across replicas |
| `03-log-history.sql` | — | `query_log_N`: logs of replaced replicas mounted read-only; the `system_tables_tracking_*` registry; full history with `clusterAllReplicas(default, merge(system, ^query_log))`; three ways of counting a week of queries |
| `04-workload.sql` | `systables_lab` | Tables, an MV, five 1M-row inserts, four reads (cache on/off, key hit/miss), a mutation — all tagged with `log_comment` |
| `05-expected-error.sql` | — | A query that must fail (`CANNOT_PARSE_DATE`); `run.sh` fails if it does not |
| `06-query-log.sql` | — | The workload in `query_log`; cache vs S3 bytes from `ProfileEvents`; marks selected by the key; failures; `query_views_log`; who fills `query_log` on Cloud; top query shapes |
| `07-parts-merges.sql` | — | `system.parts` the same on every replica, `part_log` events only on the replica that did the work, part ↔ insert through `query_id`, the mutation, outdated parts |
| `08-metrics-errors.sql` | — | cgroup vs host size, current metrics, `metric_log` per minute, `system.errors` vs `error_log`, `session_log`, the SQL behind the built-in dashboards |
| `09-kill.sh` | — | A plain `KILL QUERY` that lands on the wrong replica does nothing; `KILL QUERY ON CLUSTER 'default'` stops it |
| `99-cleanup.sql` | drops `systables_lab` | — |

`oss-diff.sh` starts an OSS server of the same release in Docker and lists the system tables
only one side has.

### Run

Needs the `clickhouse` binary (for `clickhouse client` and `clickhouse local`, which redraws
the masked tables) and a Cloud service. The workload adds a few minutes of compute; `99` drops
its database. Querying system tables keeps a service awake, so an idling service will not
idle while you run this.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh               # every step; output also goes to out/ (gitignored)
./run.sh 06 07         # only some steps (04 must have run first)
./oss-diff.sh 26.8     # optional: Cloud-only system tables, needs Docker
```

Each statement opens its own connection, as most HTTP clients and pools do, so consecutive
statements can land on different replicas. Steps 06–08 read only log rows written after `04`
started (the `systables_lab.run` table), so a re-run on the same day does not mix runs.
`system.errors` is a counter since the replica started, so it keeps counting across runs.

Captures are masked unless `MASK=0`: pod names keep only their random suffix (`2rdd723-0`), and
the bucket, the service namespace, the endpoint and e-mail addresses are replaced.

### What the 2026-11-04 run returned

- `system` held 595 tables on one replica: 26 current log tables, 397 older log generations,
  155 in-memory tables. The other replica held 483. OSS 26.8 has 153; 45 base names appear only
  on the Cloud side. Most are Cloud features (SharedMergeTree, distributed cache, merge
  coordinator, stateless workers, custom metrics); the rest are tables OSS creates only when
  configured (`session_log`, the filesystem cache logs, the Keeper tables).
- Log tables use the storage policy `plain_rewritable_system_tables`, under
  `system-tables/mergetree/<replica>/` in the service's bucket, with a 180-day TTL
  (`aggregated_zookeeper_log` and `zookeeper_connection_log`: 30 days).
- One replica mounted 28 older `query_log` tables, the other 20, each from a replica that no
  longer exists. Every origin replica appeared exactly once. History reached back 41 days
  (2026-09-24); 486 older tables in the registry were not mounted on either replica.
- A week of `query_log`: 324,448 rows on one replica's current table, 665,558 across both
  current tables, 4,964,419 with the older generations. The 50 mounted `query_log` tables had
  only 2 distinct schemas, so the generations are not one per release.
- All generations of `text_log` together: 4.59 billion rows, 80.95 GiB.
- Over the last day, 73.3% of `query_log` rows came from `*-internal` platform users, 14.8% from
  background tasks with no user, 6.8% from ClickPipes, 5.1% from everyone else.
- The full scan read 3.53 MiB from the cache and 3.18 MiB from S3 (3 GET requests);
  with `enable_filesystem_cache = 0`, 3.81 MiB from S3 in 82 GET requests and 6.57 s of thread
  time instead of 0.94 s. The primary-key range selected 6 of 615 marks (49,152 rows).
- Both replicas reported the same 5 active parts. `NewPart` events appeared only on the replica
  that ran each insert, and `DownloadPart` on the other one. All five `MutatePart` events were on
  `2rdd723-0`, although the `ALTER` had been sent to `6row3gp-0`.
- Each replica's cgroup was 2 CPUs and 8 GiB, while `OSMemoryTotal` showed the host's 266–268 GB.
- The plain `KILL QUERY` landed on the other replica and left the query running;
  `KILL QUERY ON CLUSTER 'default'` stopped it (`QUERY_WAS_CANCELLED`).

The article that walks through these results is on the notes site (Korean).

---

## 한국어

ClickHouse Cloud 서비스는 엔드포인트 하나 뒤에 레플리카가 여러 대 있고, `system` 데이터베이스의
대부분은 응답한 레플리카 한 대만 보여 줍니다. 이 실습은 어떤 테이블이 레플리카별이고 어떤 테이블이
공유되는지, 로그 테이블이 어디에 저장되는지, 레플리카가 교체돼도 로그 이력이 어떻게 남는지, 그리고
그것을 모두 읽는 쿼리 패턴(`clusterAllReplicas`, `merge()`, `KILL QUERY ON CLUSTER`)을 보여 줍니다.
직접 만든 작은 워크로드(500만 행, Materialized View, 뮤테이션, 실패하는 쿼리, 중간에 죽이는 긴 쿼리)가
로그 테이블마다 보여 줄 거리를 만듭니다.

**검증: ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 2 vCPU / 8 GiB 레플리카 2대,
fast 릴리스 채널), 2026-11-04, `01` → `99` 전체 실행 58초. `oss-diff.sh`로
`clickhouse/clickhouse-server:26.8`(26.8.36.3)과 비교했습니다.

작성: Ken Lee · MIT

### 단계별 내용

| 단계 | 쓰기 | 보여 주는 것 |
|---|---|---|
| `01-inventory.sql` | — | system 테이블의 종류(인메모리, 로그, 이전 세대 로그), 로그 테이블의 크기와 TTL, 저장되는 오브젝트 스토리지 정책과 디스크, Cloud 전용 테이블, 로깅 설정 |
| `02-replicas.sql`, `02-routing.sh` | — | 엔드포인트 뒤의 레플리카, `default`·`all_groups.default` 클러스터, 레플리카별 `query_log` 건수, 새 연결 10개가 레플리카에 나뉘는 모습 |
| `03-log-history.sql` | — | `query_log_N`: 교체된 레플리카의 로그를 읽기 전용으로 붙인 것, `system_tables_tracking_*` 레지스트리, `clusterAllReplicas(default, merge(system, ^query_log))`로 읽는 전체 이력, 일주일 쿼리 수를 세는 세 가지 방법 |
| `04-workload.sql` | `systables_lab` | 테이블, MV, 100만 행 INSERT 다섯 번, 읽기 네 번(캐시 켬/끔, 키 적중/미적중), 뮤테이션. 모두 `log_comment` 태그 |
| `05-expected-error.sql` | — | 반드시 실패해야 하는 쿼리(`CANNOT_PARSE_DATE`). 실패하지 않으면 `run.sh`가 실패 |
| `06-query-log.sql` | — | `query_log` 속 워크로드, `ProfileEvents`로 본 캐시 대 S3 바이트, 키가 고른 마크, 실패, `query_views_log`, Cloud에서 `query_log`를 채우는 주체, 상위 쿼리 형태 |
| `07-parts-merges.sql` | — | 모든 레플리카에서 같은 `system.parts`, 일한 레플리카에만 남는 `part_log`, `query_id`로 잇는 파트 ↔ INSERT, 뮤테이션, outdated 파트 |
| `08-metrics-errors.sql` | — | cgroup 대 호스트 크기, 현재 메트릭, 분 단위 `metric_log`, `system.errors` 대 `error_log`, `session_log`, 내장 대시보드의 SQL |
| `09-kill.sh` | — | 다른 레플리카에 떨어진 일반 `KILL QUERY`는 아무것도 하지 않고, `KILL QUERY ON CLUSTER 'default'`가 멈춤 |
| `99-cleanup.sql` | `systables_lab` 삭제 | — |

`oss-diff.sh`는 같은 릴리스의 OSS 서버를 Docker로 띄워 한쪽에만 있는 system 테이블을 보여 줍니다.

### 실행

`clickhouse` 바이너리(`clickhouse client`, 그리고 마스킹한 표를 다시 그리는 `clickhouse local`)와
Cloud 서비스가 필요합니다. 워크로드가 몇 분 분량의 컴퓨트를 더 쓰고, `99`가 데이터베이스를 지웁니다.
system 테이블을 조회하면 서비스가 깨어 있으므로, 실행하는 동안 idling 서비스는 쉬지 않습니다.

```bash
cp .env.example .env && chmod 600 .env   # CH_HOST, CH_USER, CH_PASSWORD
./run.sh               # 전체 단계. 출력은 out/에도 저장(gitignore)
./run.sh 06 07         # 일부 단계만(04가 먼저 실행돼 있어야 함)
./oss-diff.sh 26.8     # 선택: Cloud 전용 system 테이블, Docker 필요
```

대부분의 HTTP 클라이언트·커넥션 풀처럼 문장마다 연결을 새로 열기 때문에, 연속한 문장이 서로 다른
레플리카에 떨어질 수 있습니다. 06–08단계는 `04`가 시작된 뒤 기록된 로그만 읽으므로(`systables_lab.run`
테이블), 같은 날 다시 돌려도 실행이 섞이지 않습니다. `system.errors`는 레플리카가 시작된 뒤의
누적 카운터라 실행을 거듭하면 계속 늘어납니다.

캡처는 `MASK=0`이 아니면 마스킹합니다. 파드 이름은 무작위 접미사(`2rdd723-0`)만 남기고, 버킷·서비스
네임스페이스·엔드포인트·이메일 주소는 바꿉니다.

### 2026-11-04 실행 결과

- 한 레플리카의 `system`에 테이블 595개: 현재 로그 테이블 26개, 이전 세대 로그 397개, 인메모리 155개.
  다른 레플리카는 483개였습니다. OSS 26.8은 153개이고, Cloud 쪽에만 있는 이름이 45개입니다. 대부분은
  Cloud 기능(SharedMergeTree, 분산 캐시, merge coordinator, stateless worker, custom metrics)이고,
  나머지는 OSS가 설정했을 때만 만드는 테이블(`session_log`, 파일시스템 캐시 로그, Keeper 테이블)입니다.
- 로그 테이블은 스토리지 정책 `plain_rewritable_system_tables`로, 서비스 버킷의
  `system-tables/mergetree/<레플리카>/` 아래에 저장되고 TTL은 180일입니다
  (`aggregated_zookeeper_log`, `zookeeper_connection_log`는 30일).
- 한 레플리카는 이전 `query_log` 테이블 28개, 다른 레플리카는 20개를 붙여 두었고, 모두 지금은 없는
  레플리카가 쓴 것입니다. 원래 레플리카마다 정확히 한 번씩 나타났습니다. 이력은 41일 전(2026-09-24)까지
  보였고, 레지스트리에 있는 더 오래된 테이블 486개는 어느 레플리카에도 붙어 있지 않았습니다.
- 일주일치 `query_log`: 한 레플리카의 현재 테이블 324,448행, 두 레플리카의 현재 테이블 665,558행,
  이전 세대까지 4,964,419행. 붙어 있는 `query_log` 테이블 50개의 스키마는 두 가지뿐이라, 세대가
  릴리스마다 하나씩 생긴 것은 아닙니다.
- `text_log`는 모든 세대를 합쳐 45.9억 행, 80.95 GiB.
- 최근 하루 `query_log` 행의 73.3%는 `*-internal` 플랫폼 사용자, 14.8%는 사용자 없는 백그라운드 작업,
  6.8%는 ClickPipes, 나머지 5.1%가 그 밖의 사용자였습니다.
- 전체 스캔은 캐시에서 3.53 MiB, S3에서 3.18 MiB(GET 3회)를 읽었습니다. `enable_filesystem_cache = 0`이면
  S3에서 3.81 MiB를 GET 82회로 읽었고, 스레드 시간이 0.94초에서 6.57초가 됐습니다. 기본 키 범위 조건은
  마크 615개 중 6개(49,152행)를 골랐습니다.
- 두 레플리카가 같은 활성 파트 5개를 보고했습니다. `NewPart`는 각 INSERT를 실행한 레플리카에만,
  `DownloadPart`는 다른 레플리카에 남았습니다. `ALTER`는 `6row3gp-0`에 보냈는데 `MutatePart` 다섯 건은
  모두 `2rdd723-0`에 있었습니다.
- 레플리카의 cgroup은 2 CPU, 8 GiB였고, `OSMemoryTotal`은 호스트의 266–268 GB를 보였습니다.
- 일반 `KILL QUERY`는 다른 레플리카에 떨어져 쿼리를 그대로 두었고, `KILL QUERY ON CLUSTER 'default'`가
  멈췄습니다(`QUERY_WAS_CANCELLED`).

이 결과를 하나씩 풀어 쓴 글은 노트 사이트에 있습니다(한국어).
