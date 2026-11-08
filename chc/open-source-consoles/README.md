# Open-source ClickHouse consoles on SharedMergeTree

[English](#english) | [한국어](#한국어)

## English

Five open-source web UIs for ClickHouse, run against one ClickHouse Cloud service with the same scenarios: what they show for
SharedMergeTree tables, what happens with two replicas behind one endpoint, and what each one needs to be set up.

**Verified on ClickHouse Cloud 26.8.1.608** (AWS ap-northeast-2, 2 replicas), 2026-11-08. The tools ran in Docker on a Mac with
the images and settings `tools.sh` uses, against the service's public endpoint over HTTPS 8443, connected as the service's `default`
user; `01-setup.sql` and `99-cleanup.sql` ran with `clickhouse client`, and the long query is the one in `long-query.sh`. The two
scripts themselves were only checked with `bash -n`. The LibreDB column check also ran on OSS `clickhouse local` 26.4.5.143 and
26.8.36.3 the same day.

Author: Ken Lee · MIT

### Tools

| Tool | Version | Image |
|---|---|---|
| CH-UI | v2.33.0 | `ghcr.io/caioricciuti/ch-ui:v2.33.0` |
| chmonitor | 0.3.11 | `ghcr.io/chmonitor/chmonitor:0.3.11` |
| CH-Ops | 1.3.3 | `ghcr.io/quantrail-data/ch-ops:1.3.3` |
| CloudBeaver CE | 26.2.0 | `dbeaver/cloudbeaver:26.2.0` |
| LibreDB Studio | 1.2.0 | `ghcr.io/libredb/libredb-studio:1.2.0` |

### Scenarios

| # | What | Pass when |
|---|---|---|
| S1 | Connect | The tool reaches the service over HTTPS 8443 |
| S2 | Browse | `console_lab`'s tables, views and materialized view show, with engine names (`SharedMergeTree`, `SharedAggregatingMergeTree`) |
| S3 | Query | `SELECT event, count() FROM console_lab.events GROUP BY event` returns 3 × 700,000 |
| S6 | Running and kill | `long-query.sh` shows up as running, and killing it from the tool ends the client with `Code: 394 QUERY_WAS_CANCELLED` |
| S8 | Merges and replication | A replication page shows something sensible for SharedMergeTree, or says why it is empty |

### Results

**O** pass, **△** partial, **X** fail, **·** not run.

| Tool | S1 | S2 | S3 | S6 | S8 | Notes |
|---|---|---|---|---|---|---|
| CH-UI | O | O | O | · | · | Running queries, history and merges are in its paid tier |
| chmonitor | O | O | · | △ | · | Kill works; the running list flips between replicas (below) |
| CH-Ops | O | O | · | · | O | Says SharedMergeTree has no replication queue |
| LibreDB Studio | O | O | O | · | · | Needs `system.tables.target_database` (26.8 has it, 26.4 does not) |
| CloudBeaver CE | · | · | · | · | · | Not run against Cloud this time: its connection dialog takes the password by hand |

**CH-UI.** The table overview reads the engine as `SharedMergeTree` and shows 2,100,000 rows and 15.3 MB, with the stored
`SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')` DDL. Lineage draws `events → daily_mv → daily` and `v_buy`.
The cluster topology page lists `default` with 2 replicas and `all_groups.default` with 3 (a replica of another service in the same
warehouse is included), with internal pod names — keep that page out of shared screenshots.

**chmonitor.** A Cloud service has one endpoint in front of its replicas, and `system.processes` is per replica. Each refresh of
the running list lands on one replica, so `long-query.sh` showed on one refresh and was gone on the next. Cloud does not give out
per-replica addresses, so it cannot be pinned the way chmonitor allows with a comma list in `CLICKHOUSE_HOST`. When the query was
visible, the kill button worked: the toast said "Killed query", and the client ended with `Code: 394 QUERY_WAS_CANCELLED` (two runs).
The "Queries by user" panel also lists Cloud's own service accounts (for example `monitoring-internal`, `operator-internal`) and
ClickPipes accounts.

**CH-Ops.** Connections are added in its UI, and its first super admin must come from the environment (`SUPER_ADMIN_1*`; it does
not start without them). The replication queue page knows SharedMergeTree, and Tables & Parts shows the engines correctly. It lists
every database the account can see.

**LibreDB Studio.** Connects with SSL mode `verify-system`. On 26.8 the schema tree (2 tables, 1 view, 1 materialized view) and
queries work. Its schema query reads `system.tables.target_database`, which 26.4 does not have (`clickhouse local` 26.4.5.143: 0
columns; 26.8.36.3: 1), so against a 26.4 server the tree fails with `Code: 47 … Identifier 'mv.target_database' cannot be resolved`
while SQL still runs.

### Captures

Originals, cropped so no host name or e-mail shows (2026-11-08, Cloud 26.8.1.608):

- [`images/01-chui-table-sharedmergetree.png`](images/01-chui-table-sharedmergetree.png) — CH-UI table overview of console_lab.events: rows 2,100,000, size 15.3 MB, engine SharedMergeTree, partition key toYYYYMM(ts), sorting key event, ts, and the CREATE TABLE statement with ENGINE = SharedMergeTree
- [`images/02-chui-lineage.png`](images/02-chui-lineage.png) — CH-UI lineage of console_lab.events: events (2.1M rows, 15.3 MB) feeds the materialized view daily_mv, which writes to table daily (2.7K rows); the view v_buy is parsed from SQL
- [`images/03-chui-query.png`](images/03-chui-query.png) — CH-UI query tab: SELECT event, count(), round(sum(amount), 2) FROM console_lab.events GROUP BY event returns click, view and buy with 700,000 each, read 2.10M rows in 0.11 s
- [`images/04-chmon-running-visible.png`](images/04-chmon-running-visible.png) — chmonitor running queries filtered to sleepEachRow: one SELECT from the console-long query at 10% progress, 1.4 minutes
- [`images/05-chmon-running-other-replica.png`](images/05-chmon-running-other-replica.png) — The same chmonitor filter on another refresh: no queries match, because the request landed on the other replica
- [`images/06-chmon-killed.png`](images/06-chmon-killed.png) — chmonitor after the kill button: a toast reads Killed query console-long-chc-2
- [`images/07-chops-replication-queue-smt.png`](images/07-chops-replication-queue-smt.png) — CH-Ops Queues page, Replication Queue tab: No replicated tables — Replication monitoring is not available on this deployment. SharedMergeTree does not use a replication queue
- [`images/08-libredb-schema-query.png`](images/08-libredb-schema-query.png) — LibreDB Studio connected to console_lab: the schema tree shows Tables (daily 2.7K, events 2.1M), Views, Materialized Views (daily_mv), and the query returns click 700000

### What to plan for on SharedMergeTree

1. **Per-replica screens need `clusterAllReplicas`.** Running queries, `query_log` and server metrics are per replica. Behind one
   endpoint a tool sees whichever replica answered. Tools that query `clusterAllReplicas(default, system.processes)` see all of them;
   an account doing that needs `READ ON REMOTE`.
2. **Tool accounts.** `default` has no global `GRANT OPTION`, so `GRANT ALL` fails. `GRANT CURRENT GRANTS ON *.* TO …` hands over what
   `default` has; for `system.*` it leaves out `system.zookeeper` (`SHOW GRANTS` prints a `REVOKE` for it).
3. **No replication queue.** Pages built on `system.replication_queue` are empty, as they should be.
4. **AI features.** CH-UI, chmonitor, CH-Ops, CloudBeaver and LibreDB all have one. Decide whether query text may go to an LLM
   provider before turning them on.
5. **Cloud has its own console.** Monitoring and Query insights already cover the operations screens. On Cloud these tools earn their
   place for SQL editing, lineage and their own roles.

### Run it

```bash
cd chc/open-source-consoles
cat > .env <<'ENV'
CH_HOST=<service>.<region>.aws.clickhouse.cloud
CH_USER=default
CH_PASSWORD=<password>
ENV
chmod 600 .env
set -a; . ./.env; set +a
clickhouse client --host "$CH_HOST" --port 9440 --secure --user default --password "$CH_PASSWORD" \
  --param_admin_pw='<Admin-pw-1!>' --param_ro_pw='<Ro-pw-1!>' --multiquery < 01-setup.sql
./tools.sh up          # localhost:18501-18505
./long-query.sh        # in another terminal, for S6
./tools.sh down
clickhouse client --host "$CH_HOST" --port 9440 --secure --user default --password "$CH_PASSWORD" --multiquery < 99-cleanup.sql
```

The tools' own admin password is in `.tools.env` (generated, gitignored). CH-Ops and LibreDB need the connection added in their UI
(host, port 8443, HTTPS/SSL on). The service's IP access list must allow the machine running Docker.

---

## 한국어

ClickHouse용 오픈소스 웹 UI 다섯 개를 ClickHouse Cloud 서비스 하나에 같은 시나리오로 붙여 봤습니다. SharedMergeTree 테이블을 어떻게
보여 주는지, endpoint 하나 뒤에 replica가 둘일 때 무엇이 달라지는지, 각 도구를 띄우는 데 무엇이 필요한지 봅니다.

**ClickHouse Cloud 26.8.1.608에서 확인**(AWS ap-northeast-2, replica 2개), 2026-11-08. 도구는 `tools.sh`와 같은 이미지·설정으로 Mac의
Docker에서 띄워 서비스의 공개 endpoint(HTTPS 8443)에 서비스의 `default` 사용자로 붙였습니다. `01-setup.sql`·`99-cleanup.sql`은
`clickhouse client`로 돌렸고, 오래 도는 쿼리는 `long-query.sh`의 그 쿼리입니다. 두 스크립트 자체는 `bash -n`으로만 확인했습니다. LibreDB 관련 열 확인은 같은 날 OSS `clickhouse local` 26.4.5.143과 26.8.36.3에서도 했습니다.

작성: Ken Lee · MIT

### 도구

| 도구 | 버전 | 이미지 |
|---|---|---|
| CH-UI | v2.33.0 | `ghcr.io/caioricciuti/ch-ui:v2.33.0` |
| chmonitor | 0.3.11 | `ghcr.io/chmonitor/chmonitor:0.3.11` |
| CH-Ops | 1.3.3 | `ghcr.io/quantrail-data/ch-ops:1.3.3` |
| CloudBeaver CE | 26.2.0 | `dbeaver/cloudbeaver:26.2.0` |
| LibreDB Studio | 1.2.0 | `ghcr.io/libredb/libredb-studio:1.2.0` |

### 시나리오

| # | 무엇을 | 통과 기준 |
|---|---|---|
| S1 | 접속 | HTTPS 8443으로 서비스에 붙는다 |
| S2 | 탐색 | `console_lab`의 테이블·뷰·MV가 엔진 이름(`SharedMergeTree`, `SharedAggregatingMergeTree`)과 함께 보인다 |
| S3 | 쿼리 | `SELECT event, count() FROM console_lab.events GROUP BY event`가 3 × 700,000으로 나온다 |
| S6 | 실행 중·중지 | `long-query.sh`가 실행 중으로 보이고, 도구에서 중지하면 클라이언트가 `Code: 394 QUERY_WAS_CANCELLED`로 끝난다 |
| S8 | 머지·복제 | 복제 화면이 SharedMergeTree에 맞는 내용을 보이거나, 왜 비었는지 알려 준다 |

### 결과

**O** 통과, **△** 일부, **X** 실패, **·** 이번에 안 함.

| 도구 | S1 | S2 | S3 | S6 | S8 | 비고 |
|---|---|---|---|---|---|---|
| CH-UI | O | O | O | · | · | 실행 중 쿼리·기록·머지는 유료 등급 |
| chmonitor | O | O | · | △ | · | 중지는 된다. 실행 중 목록이 replica를 오간다(아래) |
| CH-Ops | O | O | · | · | O | SharedMergeTree에는 복제 큐가 없다고 안내 |
| LibreDB Studio | O | O | O | · | · | `system.tables.target_database`가 필요(26.8에는 있고 26.4에는 없다) |
| CloudBeaver CE | · | · | · | · | · | 이번에는 Cloud에 붙이지 않았다. 연결 창에 비밀번호를 손으로 넣어야 한다 |

**CH-UI.** 테이블 개요가 엔진을 `SharedMergeTree`로 읽고 2,100,000행, 15.3 MB를 보여 주며, 저장된 DDL
`SharedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`도 그대로 나옵니다. 계보는 `events → daily_mv → daily`와 `v_buy`를
그립니다. 클러스터 구성 화면에는 `default`(replica 2개)와 `all_groups.default`(3개, 같은 warehouse의 다른 서비스 replica 포함)가 내부
pod 이름과 함께 나오니 공유용 캡처에서는 빼 두세요.

**chmonitor.** Cloud 서비스는 replica 앞에 endpoint가 하나이고 `system.processes`는 replica마다 따로입니다. 실행 중 목록은 새로 고칠
때마다 한 replica에 닿기 때문에 `long-query.sh`가 한 번은 보이고 다음에는 사라졌습니다. Cloud는 replica별 주소를 주지 않아 chmonitor의
`CLICKHOUSE_HOST` 쉼표 목록으로 고정할 수도 없습니다. 보일 때 중지 버튼을 누르면 "Killed query" 알림이 뜨고 클라이언트는
`Code: 394 QUERY_WAS_CANCELLED`로 끝났습니다(두 번 확인). "Queries by user"에는 Cloud 자체 서비스 계정(`monitoring-internal`,
`operator-internal` 등)과 ClickPipes 계정도 나옵니다.

**CH-Ops.** 연결은 화면에서 추가하고, 첫 super admin은 환경 변수(`SUPER_ADMIN_1*`)로만 만듭니다(없으면 시작하지 않습니다). 복제 큐
화면이 SharedMergeTree를 알아보고, Tables & Parts의 엔진도 맞습니다. 계정이 볼 수 있는 모든 데이터베이스가 나옵니다.

**LibreDB Studio.** SSL 모드 `verify-system`으로 붙습니다. 26.8에서는 스키마 트리(테이블 2, 뷰 1, MV 1)와 쿼리가 모두 됩니다. 스키마
쿼리가 `system.tables.target_database`를 읽는데 26.4에는 이 열이 없어서(`clickhouse local` 26.4.5.143: 0개, 26.8.36.3: 1개) 26.4 서버에서는
트리가 `Code: 47 … Identifier 'mv.target_database' cannot be resolved`로 깨지고 SQL 실행만 됩니다.

### 캡처

원본입니다. 호스트 이름·이메일이 보이지 않게 잘랐습니다(2026-11-08, Cloud 26.8.1.608).

- [`images/01-chui-table-sharedmergetree.png`](images/01-chui-table-sharedmergetree.png) — CH-UI `events` 개요: 2,100,000행, 15.3 MB, 엔진 SharedMergeTree, 저장된 DDL
- [`images/02-chui-lineage.png`](images/02-chui-lineage.png) — CH-UI 계보: events → daily_mv → daily, v_buy
- [`images/03-chui-query.png`](images/03-chui-query.png) — CH-UI 집계 쿼리: click·view·buy 각 700,000, 0.11초
- [`images/04-chmon-running-visible.png`](images/04-chmon-running-visible.png) — chmonitor 실행 중 목록에 console-long 쿼리가 보일 때
- [`images/05-chmon-running-other-replica.png`](images/05-chmon-running-other-replica.png) — 같은 필터, 다른 replica에 닿은 새로 고침: 일치하는 쿼리 없음
- [`images/06-chmon-killed.png`](images/06-chmon-killed.png) — chmonitor 중지 후 알림 "Killed query console-long-chc-2"
- [`images/07-chops-replication-queue-smt.png`](images/07-chops-replication-queue-smt.png) — CH-Ops 복제 큐: "SharedMergeTree does not use a replication queue"
- [`images/08-libredb-schema-query.png`](images/08-libredb-schema-query.png) — LibreDB Studio 스키마 트리(테이블 2, MV 1)와 쿼리 결과

### SharedMergeTree에서 챙길 것

1. **replica별 화면은 `clusterAllReplicas`가 있어야 한다.** 실행 중 쿼리, `query_log`, 서버 지표는 replica별입니다. endpoint 하나 뒤에서는
   응답한 replica만 보입니다. `clusterAllReplicas(default, system.processes)`로 읽는 도구라야 전부 보이고, 그 계정에는 `READ ON REMOTE`가
   필요합니다.
2. **도구용 계정.** `default`에 전역 `GRANT OPTION`이 없어 `GRANT ALL`은 실패합니다. `GRANT CURRENT GRANTS ON *.* TO …`가 `default`의 권한을
   넘겨 줍니다. `system.*`에 쓰면 `system.zookeeper`는 빠집니다(`SHOW GRANTS`에 `REVOKE`로 나옵니다).
3. **복제 큐가 없다.** `system.replication_queue` 기반 화면은 비어 있는 게 정상입니다.
4. **AI 기능.** CH-UI, chmonitor, CH-Ops, CloudBeaver, LibreDB 모두 있습니다. 켜기 전에 쿼리 내용이 LLM 공급자로 나가도 되는지 정하세요.
5. **Cloud에는 자체 콘솔이 있다.** 운영 화면은 Monitoring·Query insights가 이미 맡습니다. Cloud에서 이 도구들의 쓸모는 SQL 편집, 계보,
   도구 자체 역할 쪽입니다.

### 돌려 보기

위 English 절의 명령 그대로입니다. 도구 관리자 비밀번호는 `.tools.env`(자동 생성, gitignore)에 있습니다. CH-Ops와 LibreDB는 화면에서
연결(호스트, 포트 8443, HTTPS/SSL 켬)을 추가합니다. 서비스의 IP access list가 Docker를 돌리는 머신을 허용해야 합니다.
