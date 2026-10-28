# Case study: a telco OSS data lake — architecture, use cases, what a PoC verified

[English](#english) | [한국어](#한국어)

---

## English

A telco **OSS** (operations: equipment, faults, quality; not BSS, which is billing) collects logs,
metrics and events from every device on the network (UE: phones, IoT modules, vehicles, routers)
and from the network equipment itself. This lab shows **who uses that data, and how**: a reference
architecture for a typical telco OSS lake, the use cases built on it (NOC map,
dashboards, ad hoc analysis, request/response serving, subscriptions, bulk export, schema contracts,
data quality, pipeline observability, lake history, AI agents, Managed Postgres as an expansion),
and a small ClickHouse lake that actually runs five of them.

It is made to be shown to colleagues as a case study: situation → the industry trend (virtualizing
the OSS data layer, from public sources) → architecture → use cases → features verified in the PoC →
lessons → try it, with next steps. A static page in English (default, at `/`), Korean, Japanese and
Chinese works without ClickHouse; a local live demo has a "send next minute" button. Dark only, with
the colours of clickhouse.com (computed styles, read 2026-10-18).

A composite scenario: a fictional operator and fictional cities, built from common telco OSS practice
(medallion layering over 3GPP-style data). The lab runs device (UE) traces only; performance counters
(PM), alarms (FM) and complaints (VoC) appear as sources in the figure, not as tables. Names are
invented and figures are measured in this lab on generated data at reduced scale (180,000 rows a
minute, three cities, about 20,000 grid cells, far below a real operator's trace intake). The cities
sit in open ocean, so no coordinate points to a real place. IMSIs use the test network code 001-01.
Measurements use LTE terms (RSRP/RSRQ/SINR, TS 36.214); each one's location is assumed to come from
MDT (TS 37.320) location reports or positioning, mapped to an H3 res-9 **grid cell** (about 0.1 km²).
A grid cell is a location bucket, not a radio cell or sector.

**Verified on ClickHouse 26.9.13.15** (`clickhouse/clickhouse-server:26.9.13.15`), 2026-10-18:
`tools/hol run usecase/oss-network-quality-lake` passes (01–05 and 99, about 30 s; two runs in a row after the last change), and the live demo was run
with `ui/up.sh` and its button pressed several times. Machine: Apple M4 Pro, macOS, Docker Desktop;
the container sees 12 CPUs and 7.75 GiB.

### Reference architecture

Sources (devices, base stations, servers, applications) → collection (an agent per node, an
aggregator) → raw messages on a message bus (Kafka) → stream processing that maps to an industry
information model and enriches → curated messages → sink → storage: history in an open-table-format
lake, ready-to-use summaries (gold) in **ClickHouse** → serving in three ways (request/response over
HTTP, bulk export, subscription) → NOC screens, dashboards, analysts, business apps, AI agents.
Two rails run along it: a **schema contract in Git** from which every stage's schema and DDL is
generated, and a **control-plane API** that declares, deploys and observes every component.

### Use cases

| Group | Use case | In this lab |
|---|---|---|
| Seeing | NOC map: busiest grid cells, weakest grid cells (known gaps left out), an area whose signal just dropped | run (`cell_rank_now`, `uc_alert_cells`) |
| Seeing | Dashboard: KPI per minute and city | run (`uc_dashboard`) |
| Seeing | Ad hoc analysis: weak signal downtown vs edge | run (`uc_analysis`) |
| Serving | Request/response over HTTP, streamed row by row | run (ClickHouse HTTP interface) |
| Serving | Subscription: alerts every minute; push to a Kafka topic | alerts run (`uc_alert_areas`); Kafka publish is an example (`examples/subscribe-kafka.sql`) |
| Serving | Bulk export | described |
| Serving | Managed Postgres for subscriptions, keys, watermarks; `pg_clickhouse` joins the lake from Postgres | expansion example (`examples/postgres-pg-clickhouse.sql`, pattern verified in clickhouse-managed-postgres-hols) |
| Running | Schema contract in Git → generated DDL | described |
| Running | Data quality at every stage | run (silver drops rows without a cell or subscriber, keeps missing RSRP as NULL) |
| Running | Pipeline observability (ClickStack) | described |
| Running | Lake history (Iceberg) joined with gold | described |
| AI | Agents turn questions into SQL over MCP/HTTP; agent observability (Langfuse) | described |

Every minute the generator injects a 22 dB drop into one res-7 area (about 49 grid cells), so the
alert use case and the live feed have something new to carry each minute. That shows pipeline
latency, not detection quality: the rule (12 dB below the previous 59 minutes, folded per res-7
area) is built to find exactly what is injected. Real rules also watch measurement counts
collapsing, persistence over several minutes and recent configuration changes.

Coverage comes from distance to the serving site (one per res-8 area downtown, one per res-7 area
further out), a fixed offset per site and per city, and a little extra loss with distance from the
centre, so the three cities differ. Known coverage gaps (`known_weak` in the inventory) are left out
of the "weakest 10" so that newly weak places show. PCI is fixed per serving site.

### Features verified in the PoC

Ingest as received · cleaning at insert time (MV) · enrichment from an inventory dictionary (`dictGet`,
district names) · pre-aggregation at insert (cell × 1 min) · gold on gold (cell × 10 min cascading from
cell × 1 min, equal to raw) · a geography axis (district × 1 min) · an answer refreshed every minute
(refreshable MV) · the same 20 rows from every stage · sudden-drop alerts · HTTP serving with a
read-only user · H3 geo functions. Each has a check in 03–05, except "20 rows readable during
refreshes" and "the read-only user cannot write", which were checked by hand on 2026-10-18.

### Lessons (a–c measured 2026-10-18 on this lab, 26.9.13.15; d–f are practice, not measured)

- Nullable costs mostly in query complexity: the NOC query on bronze needs `assumeNotNull`,
  `IS NOT NULL`, `stringToH3`, `cityHash64`; on silver it does not.
- A uniq state is sized by distinct values per group, not by input type: 300 distinct values give
  1,203 B for `String` and for `UInt64` alike; `uniqCombined(12)` is 2,651 B at 300 and at 1,000,
  where `uniq` is 4,003 B. In the lab the 1-minute rollup holds 2.43 M states of 34 B on average,
  the 10-minute one 264 K of 193 B: choose the grain where user counts live.
- Build coarse rollups from fine ones (cascading MV on the 1-minute table, `uniqMergeState` + sums);
  not a refreshable MV with `APPEND`, which by design double-inserts when its window is wider than its
  interval (reasoned, not reproduced here).
- A time column named for local time but typed UTC shifts buckets and TTL by the UTC offset; store
  instants with an explicit time zone.
- Many consumers (dashboards, an AI agent over MCP, a catalogue, Kafka Connect batches) need their own
  users and limits: read-only users with result and time limits, larger batches or async inserts.
- A pseudonymous trace is still personal data (see "Subscriber data" below).

### Subscriber data

Bronze holds a vendor-supplied hash of the IMSI. Here it is an unkeyed SHA-256 of a test PLMN plus a
10-digit MSIN, which can be reversed by trying every number in that range: a real deployment must not
rely on an unkeyed hash. Silver replaces it with `cityHash64`, a stable 64-bit pseudonym, not
anonymous data: a grid cell, a millisecond timestamp and a fixed hash per row are enough to rebuild one
subscriber's movements, and a cell-minute's `users` can be 1. Pseudonymised data stays personal data
(GDPR Recital 26, Art. 4(5)). In production: hash with a key held outside the lake (HMAC) and rotate it,
keep the row-level stages narrow and short-lived, and hide counts below a minimum in served results.

### The layers this lab runs

In the reference architecture raw messages and standardization live in Kafka and stream processing.
To keep the flow visible in one place, this lab keeps all four stages inside ClickHouse and links them
with materialized views. All four are tables in database `oss_lake` (Atomic).

| Step | Layer | Table | What happens | Rows (2 h) |
|---|---|---|---|---:|
| 1 | devices | `synth_traces` (parameterized view) | 180,000 measurements a minute across three cities | — |
| 2 | bronze | `ue_trace_raw` | kept as received: H3 as a string, the IMSI as a vendor-supplied hash (44-char base64), everything Nullable, daily partition, TTL 1 day (whole parts dropped) | 21,600,000 |
| 3 | silver | `ue_trace` ← MV | `stringToH3`, `cityHash64(imsi)`, Float32, only `rsrp` stays Nullable; rows without a cell or a subscriber are dropped | 21,470,291 |
| 4 | gold | `cell_kpi_1m` ← MV | AggregatingMergeTree, one row per (minute, cell): `uniqState(imsi_hash)` + SimpleAggregateFunction sums | 2,431,595 |
| 5 | serving | `cell_rank_now` ← refreshable MV | `REFRESH EVERY 1 MINUTE TO`, no `APPEND`: the 20 rows, replaced in one swap | 20 |
| 6 | NOC map | — | the 20 cells drawn from `h3ToGeoBoundary`, on a res-7 density background | — |

Row counts measured 2026-10-18 on a fresh run (they move slightly between runs because the data is
seeded from the start minute).

"The last hour" ends at `max(params.anchor_ts)`, not `now()`, so the lab still answers the question
whenever it is opened; the live feed moves the anchor one minute per press. **In production the
queries and the refreshable MV would use `now()`.** The TTLs are real (wall clock): bronze and silver
keep 1 day, gold 2 days, each with daily partitions and `ttl_only_drop_parts = 1`, so expiry drops
whole parts instead of rewriting them, and a partition can stay up to a day past its TTL. Reload the
lab rather than reopening an old container.

### Same answer from every layer

`03-queries.sql` asks the NOC question of each layer through four views (`noc_from_bronze`,
`_silver`, `_gold`, `_serving`), refreshes serving, and fails unless all four return the same 20
rows (serving is frozen into a Memory table first, because the scheduled refresh may swap it during
the checks). The check was seen to fire: changing one serving row by hand made it stop with
`bronze differs from serving`, and it caught the wrong-result bug described below
(`silver differs from serving`).

Query time per layer (2026-10-18, machine above, median of 5 runs after one warm-up, server-side
`elapsed_ns`, query cache off) — for reference, not a benchmark:

| Layer | Rows read | Time |
|---|---:|---:|
| bronze | 10,807,707 | 729 ms |
| silver | 10,742,720 | 229 ms |
| gold | 1,219,180 | 205 ms |
| serving | 20 | 1.5 ms |

Generating the two hours (`02-generate.sql`) took 16.5 s. One live-feed press: 180,000 rows into
bronze in 0.17–0.23 s, 0.42–0.48 s including the serving refresh (three presses); after them the
four `/api/q/<n>` answers were still identical.

### A wrong result met on the way (26.6–26.9)

Two early `tools/hol run`s failed the same-20-rows check: silver returned a few rows fewer than bronze
for the same hour. Cause, measured 2026-10-18: for a `DateTime64(3)` primary-key column, the
condition `event_ts < <a DateTime value>` becomes the key condition `event_ts <= <that value> - 1 s`
(`EXPLAIN indexes = 1` shows `event_ts in (-Inf, 1792313039]` for `< '2026-10-18 08:44:00'`). A
granule that starts inside the last second (here at `08:43:59.003`, 3,033 rows) is skipped, so its
rows vanish from `WHERE` while `countIf` with the same condition still counts them. It depends on
where granule boundaries fall, which is why it came and went between runs.

A minimal reproduction: one `DateTime64(3)` column, `index_granularity = 1000`, 5,000 rows 2 ms apart
**starting 3 ms after a whole second**, so that a granule begins inside the last second before the
bound; then `WHERE ts < toDateTime('… 00:00:09')`. It returns 4,000 rows instead of 4,499 on
26.6.8.7, 26.8.22.13 and 26.9.13.15, and the correct count on 25.8.33.6. With rows starting exactly on
the second the granules start on the second and the result is correct, which is why a careless repro
passes (rechecked 2026-10-18 on 26.9.13.15 in review). Whether it is already reported upstream was not
checked.

The lab compares `event_ts` with a `DateTime64(3)` bound (`toDateTime64(…, 3)`, the key condition is
then `(-Inf, '1792313040')`), and the run that had shown the bug passed with that change. Gold's
`bucket` is a `DateTime` compared with a `DateTime`, so it is not affected.

### The one pitfall: an aggregate state that no longer matches its source

An `AggregateFunction` column's argument type must match the source column, Nullable included.
`pitfall.sql` reproduces it in a scratch database (`tools/hol` does not run it; it fails on purpose).
Measured 2026-10-18:

- A mismatch the server can see is refused **at CREATE**: `avgState(rsrp)` over a `Nullable(Float32)`
  into `AggregateFunction(avg, Float32)` fails with `CANNOT_CONVERT_TYPE` on 25.8.33.6, 26.6.8.7,
  26.8.22.13 and 26.9.13.15.
- A mismatch that arrives later is not: the source column was `Float32`, the MV was created, then
  `ALTER TABLE … MODIFY COLUMN rsrp Nullable(Float32)` **succeeded**, and every INSERT after it failed
  (26.9.13.15):

  ```
  Code: 70. DB::Exception: Conversion from AggregateFunction(avg, Nullable(Float32)) to
  AggregateFunction(avg, Float32) is not supported: while converting source column avg_rsrp_st to
  destination column avg_rsrp_st: while pushing to view oss_pitfall.kpi_mv … (CANNOT_CONVERT_TYPE)
  ```

  The source row was written anyway (`trace` 2 rows, `kpi` 1 row), so the source keeps growing while
  the aggregate silently stops.

The lab's gold layer avoids it by keeping rsrp as plain sums (`count(rsrp)`, `sum(ifNull(rsrp, 0))`)
and feeding `uniqState` a non-Nullable hash. Another fix is a state type that follows the source
(`AggregateFunction(avg, Nullable(Float32))`).

### Files

| File | What it does |
|---|---|
| `01-schema.sql` | database, `params`, `grid`, the four layer tables, both MVs, the refreshable MV, read-only user `oss_reader` |
| `02-generate.sql` | the cell grid (3 cities × 6,769 res-9 cells, a weak-coverage spot per city), the `synth_traces` view, two hours of traces |
| `03-queries.sql` | the NOC query on each layer, `SYSTEM REFRESH VIEW`, the same-20-rows check |
| `04-usecases.sql` | use-case views (analysis, dashboard, alerts per cell and per area) and their checks |
| `05-lessons.sql` | lesson checks: the 10-minute rollup built on the 1-minute one equals raw (with a control), the region rollup adds up, bronze keeps every row; uniq state sizes by type, distinct values and grain |
| `examples/` | patterns not run here: publishing alerts to Kafka, reading the lake from Postgres with `pg_clickhouse` |
| `99-cleanup.sql` | drops `oss_lake`, `oss_pitfall` and the user |
| `pitfall.sql` | the pitfall above, by hand |
| `snapshot.sh` | writes `site/data/snapshot.json` (counts, sample rows, the 20 cells with boundaries, query times) and rebuilds the pages |
| `site/` | explainer (`explainer.html`), shared CSS/JS, catalogues `i18n/{ko,en,ja,zh}.json`, `build.py` |
| `ui/server.py` | stdlib-only server: explainer at `/`, demo at `/demo`, fixed endpoints `/api/layers`, `/api/q/<1-4>`, `/api/map`, `POST /api/tick` |
| `ui/demo.html` | the live demo page (no build step, no CDN) |
| `ui/up.sh` | container + 01–05 + server, in one command |
| `site/data/replay.json` | six live-feed presses recorded with `ui/server.py --record 6`, replayed by the demo where there is no ClickHouse |
| `vercel.json` | deployment: `python3 site/build.py` → `site/dist`, the `api/index.py` function, `noindex` header, `/en/` redirects |
| `api/index.py` | Vercel function: the demo's read-only GET endpoints against the lake on Cloud |
| `cloud/load.py`, `cloud/feed.sql` | load the lab into a Cloud service (with the Cloud differences), self-running feed, stop switch, drop |

### Run it

SQL only, in a throwaway container:

```bash
tools/hol run usecase/oss-network-quality-lake
```

The explainer without ClickHouse (pages are built from the committed snapshot):

```bash
python3 usecase/oss-network-quality-lake/site/build.py
open usecase/oss-network-quality-lake/site/dist/index.html
```

The live demo (Docker and Python 3; local only, no Cloud cost):

```bash
usecase/oss-network-quality-lake/ui/up.sh
```

Then open <http://localhost:8765/> (explainer) or <http://localhost:8765/demo> (demo; `/ko/demo`,
`/ja/demo`, `/zh/demo` for the other languages). ClickHouse listens on `127.0.0.1:18123`
(`CH_PORT` to change). Reads go through the read-only user `oss_reader`; only `POST /api/tick`
writes, and it runs one fixed statement (the next minute from `synth_traces`), never SQL from the
page. Stop with Ctrl-C and remove the container with `docker rm -f oss-lake-demo`.

After changing the SQL, refresh the snapshot against a loaded container:
`CH_URL=http://localhost:18123 usecase/oss-network-quality-lake/snapshot.sh`.

### On ClickHouse Cloud (live site)

<https://oss-lake.clickhouse.kr/> is live data, not a recording:

- **Lake**: database `oss_lake` on a ClickHouse Cloud service on AWS, loaded
  2026-10-18 on 26.6.1 by `cloud/load.py`. That is the same 01–05 files plus the Cloud differences
  listed in its docstring. All checks in 03–05 passed there.
- **Feed**: `cloud/feed.sql` adds two refreshable MVs. `feed_rmv` generates the next minute every
  minute (up to five to catch up after a pause, never a minute twice). `anchor_rmv` then moves the
  lake's "now"; the serving refresh depends on it. The TTLs come from `01-schema.sql` (bronze and
  silver 1 day, gold 2 days, whole parts dropped), so a feed that never stops keeps the lake the same
  size. `params` (one row a minute) has none, so a long pause cannot empty the lake's clock. `feed start`
  restarts the clock one minute ago when it is more than five minutes behind, so the gap is skipped,
  not replayed. The live demo says "stopped" when no new minute has arrived for three minutes.
- **Site**: Vercel project `oss-lake`. The pages are static. `api/index.py` serves the demo's GET
  endpoints as the read-only user `oss_reader`: `readonly = 1`, 20 s, 30 M rows read and 200,000-row
  result limits, an hourly quota (3,000 queries, 5 G rows read), a 20 s edge cache. The edge cache key
  is the full URL, so the function refuses any query string (400) and redirects a trailing slash
  (308) without querying ClickHouse. Errors return a fixed body; the detail goes to the function log.
  It has no write endpoint (POST returns 405). When the function cannot reach ClickHouse or the quota
  is spent, the demo falls back to the recorded minutes. Every endpoint reads a bounded window:
  on 2026-10-28 (feed always on since 2026-10-19, bronze holding one to two days) the data-quality
  counts behind `/api/layers` still scanned all of bronze, read 132.66 M rows, hit the 30 M limit,
  and the demo had fallen back to the recording; they now count the last minute (180,000 rows).
  Pages and function answer with a
  Content-Security-Policy (`default-src 'self'`, inline scripts and styles allowed, `frame-ancestors
  'none'`), `X-Frame-Options: DENY` and a Permissions-Policy that turns off camera, microphone,
  location, payment and USB (`vercel.json`).

```bash
cd usecase/oss-network-quality-lake
set -a; . /path/to/your-service.env; set +a   # CH_HOST, CH_USER, CH_PASSWORD (an admin of your service)
python3 cloud/load.py                 # load (generated passwords go to .env.cloud here, or $OSS_LAKE_SECRETS)
python3 cloud/load.py harden          # on a lake loaded before 2026-10-18: reader limits + quota, no params TTL
python3 cloud/load.py feed stop       # the stop switch; `feed start` resumes, `feed status` shows it
python3 cloud/load.py drop            # remove the database and both users
vercel deploy --prod --scope litkhai  # site + function (env: CH_URL, CH_READ_USER, CH_READ_PASSWORD)
```

Measured 2026-10-18 on that service (2 replicas, 8 GiB minimum each, 2 vCPUs):

- Load times: 01 in 9 s, 02 in 66 s, 03 in 15 s, 04 in 2 s, 05 in 12 s.
- The feed ran with no failed refresh, writing 180,000 rows a minute, and the lake's "now" stayed
  within the current wall-clock minute.
- Through the function, network included: `/api/q/1` (bronze) took 3.9 s, `/api/q/4` (serving)
  0.35 s.
- A write as `oss_reader` was refused with `ACCESS_DENIED`.

Found on the way: the inventory dictionary has a copy on each replica. `SYSTEM RELOAD DICTIONARY`
reloaded one replica, the other kept a copy loaded while the inventory was still empty, and every
silver row of the history load got an empty district. The 05 check caught it. The loader now
reloads `ON CLUSTER 'default'` and waits until every replica holds the whole inventory. The dictionary
also reloads itself every 5–10 minutes (`LIFETIME(MIN 300 MAX 600)`). District names are written into
silver and gold at insert, so after an inventory change: reload on every replica, then reprocess the
affected window.

The checks in 05 look at the last complete hour before the lake's "now", not at whole tables, so they
still hold days after a load although the layers keep different TTLs. They assume an unbroken hour;
right after `feed start` skipped a gap, wait an hour before rerunning them. The bronze check fails on a
whole missing minute as well as on a partial or duplicated one (checked 2026-10-18 by deleting one
minute from a local lake: "bronze is missing a minute").

Cost, estimated 2026-10-18:

- The service already runs around the clock (idle scaling off), so its base compute is not caused
  by the lab.
- Added, estimated 2026-10-18 for the first TTLs (3 days raw, 7 days gold): about 0.11 TB of
  storage including one daily backup, at $27.50 per TB-month (the published rate for the service's
  region, read 2026-10-18), so about $3 a month; plus the feed's compute, roughly a second of CPU a
  minute.
- Re-estimated 2026-10-19 for the current TTLs (1 day, gold 2 days), from the Cloud lake's 2-hour
  sizes on 2026-10-18 22:34 UTC extrapolated linearly (not measured at steady state): bronze about
  11 GB, silver 4.2 GB, gold 1-minute 2.3 GB, district 1.9 GB, 10-minute 1.4 GB, about 21 GB in all;
  with a daily backup roughly double, so about $1.2 a month at the same rate.
- If idle scaling is turned on later, the feed keeps the service awake. Stop it first.

### Languages

Korean is the source. `site/i18n/{ko,en,ja,zh}.json` is one catalogue per language, shared by the
explainer and the demo; `build.py` writes `/` (en), `/ko/`, `/ja/`, `/zh/` and fails when the key
sets differ (seen: removing `cta.note` from `ja.json` stopped the build with
`ja.json: missing ['cta.note']`). SQL, table and column names are not translated. Checked in the
browser on 2026-10-18 at 320 px and desktop width, light and dark, in all four languages.

### Not covered

- Scale: two hours, about 20k cells. The point is the flow, not the size.
- Real probe formats, real IMSI encryption, Kafka or object-storage ingestion: bronze is filled by SQL.
- Publishing to the notes site (`web` is not set).

### Author

Ken Lee (ClickHouse SA) · License: MIT

---

## 한국어

통신사 **OSS**(운영: 장비, 장애, 품질. 요금·청구를 다루는 BSS가 아님)는 망에 붙은 모든 단말(UE: 휴대폰,
IoT 모듈, 차량, 공유기 등)과 망 장비의 로그, 지표, 이벤트를 모읍니다. 이 실습은 **그 데이터를 누가
어떻게 쓰는지**를 보여 줍니다. 전형적인 통신사 OSS 레이크의 참조 구조, 그 위의 유즈케이스(NOC
지도, 대시보드, 즉석 분석, 즉시 조회 서빙, 구독, 대량 추출, 스키마 계약, 데이터 품질, 파이프라인 관측,
레이크 이력, AI 에이전트, 확장안으로 Managed Postgres), 그리고 그중 다섯 가지를 실제로 돌리는 작은
ClickHouse 레이크입니다.

동료들과 나누는 사례 연구입니다. 상황 → 업계 흐름(OSS 데이터 레이어의 가상화, 공개 자료) → 아키텍처 →
유즈케이스 → PoC에서 검증한 기능 → 배운 것 → 직접 해 보기와 다음 단계 순서입니다. 정적 페이지는 영어(기본,
`/`), 한국어, 일본어, 중국어로 ClickHouse 없이 열리고, 로컬 라이브 데모에는 "다음 1분 보내기" 버튼이
있습니다. 다크 모드 전용이며 clickhouse.com의 색(계산된 스타일, 2026-10-18 확인)을 씁니다.

합성 시나리오입니다. 가상의 통신사와 가상의 도시를 두고, 흔한 통신 OSS 관행(3GPP 형태의 데이터 위에
메달리온 계층)으로 구성했습니다. 실습이 돌리는 것은 단말(UE) 트레이스뿐이고, 성능 카운터(PM)·경보(FM)·
고객 불만(VoC)은 그림 속 원천일 뿐 테이블은 없습니다. 이름은 지어낸 것이고, 수치는 축소한 규모의 생성
데이터(분당 180,000행, 도시 3개, 격자 약 20,000개 — 실제 통신사의 트레이스 유입보다 훨씬 작음)로 이
실습에서 잰 값입니다. 도시는 먼 바다 위에 두어 어떤 좌표도 실제 장소를 가리키지 않습니다. IMSI는 시험망
코드 001-01을 씁니다. 측정은 LTE 용어(RSRP/RSRQ/SINR, TS 36.214)를 쓰고, 측정 위치는 MDT(TS 37.320)
위치 보고나 측위 결과를 H3 res-9 **격자**(약 0.1 km²)로 바꾼 것으로 가정합니다. 격자는 위치 단위이지
무선 셀이나 섹터가 아닙니다.

**ClickHouse 26.9.13.15에서 검증** (`clickhouse/clickhouse-server:26.9.13.15`), 2026-10-18:
`tools/hol run usecase/oss-network-quality-lake` 통과(01–05와 99, 약 30초. 마지막 변경 뒤 연속 두 번). 라이브 데모는 `ui/up.sh`로
띄워 버튼을 여러 번 눌러 확인했습니다. 기기: Apple M4 Pro, macOS, Docker Desktop, 컨테이너는
CPU 12개와 7.75 GiB를 봅니다.

### 참조 구조

원천(단말, 기지국, 서버, 애플리케이션) → 수집(노드마다 에이전트, 집계기) → 메시지 버스(Kafka)의 원천
메시지 → 업계 표준 정보 모델에 맞추고 부가 정보를 붙이는 스트림 처리 → 정제된 메시지 → 싱크 → 저장:
이력은 오픈 테이블 포맷 레이크, 바로 쓰는 요약(골드)은 **ClickHouse** → 세 가지 서빙(HTTP 즉시 조회,
대량 추출, 구독) → NOC 화면, 대시보드, 분석가, 업무 앱, AI 에이전트. 옆으로 두 줄이 함께 갑니다.
모든 단계의 스키마와 DDL을 만드는 **Git의 스키마 계약**, 모든 구성 요소를 선언하고 배포하고 관측하는
**컨트롤 플레인 API**입니다.

### 유즈케이스

| 묶음 | 유즈케이스 | 이 실습에서 |
|---|---|---|
| 보기 | NOC 지도: 가장 붐비는 격자, 가장 약한 격자(이미 아는 음영 지역 제외), 방금 신호가 떨어진 지역 | 실행 (`cell_rank_now`, `uc_alert_cells`) |
| 보기 | 대시보드: 분·도시별 KPI | 실행 (`uc_dashboard`) |
| 보기 | 즉석 분석: 도심과 외곽의 약한 신호 | 실행 (`uc_analysis`) |
| 서빙 | HTTP 즉시 조회, 한 행씩 흘려 받기 | 실행 (ClickHouse HTTP 인터페이스) |
| 서빙 | 구독: 1분마다 알림, Kafka 토픽으로 발행 | 알림 실행 (`uc_alert_areas`), Kafka 발행은 예시 (`examples/subscribe-kafka.sql`) |
| 서빙 | 대량 추출 | 설명 |
| 서빙 | 구독·키·워터마크는 Managed Postgres에, `pg_clickhouse`로 Postgres에서 레이크 조인 | 확장 예시 (`examples/postgres-pg-clickhouse.sql`, 방식은 clickhouse-managed-postgres-hols에서 검증) |
| 운영 | Git 스키마 계약 → DDL 생성 | 설명 |
| 운영 | 단계마다 데이터 품질 확인 | 실행 (실버가 셀·가입자 없는 행을 버리고, 없는 RSRP는 NULL로 유지) |
| 운영 | 파이프라인 관측 (ClickStack) | 설명 |
| 운영 | 레이크 이력(Iceberg)과 골드 조인 | 설명 |
| AI | 에이전트가 MCP/HTTP로 질문을 SQL로 바꿔 조회, 에이전트 관측(Langfuse) | 설명 |

생성기는 1분마다 res-7 지역 하나(격자 약 49개)에 22 dB 하락을 넣습니다. 그래서 알림 유즈케이스와
라이브 데모가 매분 새로 실어 나를 것이 생깁니다. 이것은 검출 품질이 아니라 파이프라인 지연을 보여
줍니다. 규칙(직전 59분보다 12 dB 아래, res-7 지역으로 묶음)이 넣은 것을 그대로 찾도록 만들어져 있기
때문입니다. 실제 규칙은 측정 수 급감, 몇 분 이상 지속, 최근 설정 변경도 함께 봅니다.

커버리지는 서빙 사이트(도심은 res-8 지역마다, 바깥은 res-7 지역마다 하나)까지의 거리, 사이트와 도시마다
고정된 오프셋, 도심에서 멀어질수록 조금 더해지는 손실로 정합니다. 그래서 세 도시가 서로 다릅니다.
이미 아는 음영 지역(인벤토리의 `known_weak`)은 "신호 약한 10"에서 빼서 새로 약해진 곳이 보이게 합니다.
PCI는 서빙 사이트마다 고정입니다.

### PoC에서 검증한 기능

받은 그대로 적재 · 적재 순간의 정제(MV) · 인벤토리 Dictionary로 보강(`dictGet`, 지역 이름) · 적재 시
사전 집계(셀 × 1분) · 골드 위의 골드(셀 × 1분에서 이어받는 셀 × 10분, 원본과 일치) · 지리 축(지역 ×
1분) · 1분마다 새로 고치는 답(Refreshable MV) · 모든 단계에서 같은 20행 · 급격한 하락 알림 · 읽기
전용 사용자의 HTTP 서빙 · H3 지리 함수. 각각 03–05에 검사가 있고, '새로 고침 중에도 20행'과 '읽기
전용 사용자는 쓰지 못함'은 2026-10-18 손으로 확인했습니다.

### 배운 것 (a–c는 2026-10-18 이 실습에서 26.9.13.15로 측정, d–f는 실무 지침이며 측정하지 않음)

- Nullable의 비용은 주로 질의의 복잡도입니다. 브론즈의 NOC 질의에는 `assumeNotNull`, `IS NOT NULL`,
  `stringToH3`, `cityHash64`가 필요하고 실버에서는 필요 없습니다.
- uniq 상태의 크기는 입력 타입이 아니라 그룹당 서로 다른 값의 수가 정합니다. 300개면 `String`과
  `UInt64` 모두 1,203 B, `uniqCombined(12)`는 300개와 1,000개 모두 2,651 B(그때 `uniq`는 4,003 B).
  이 실습의 1분 요약은 평균 34 B 상태 243만 개, 10분 요약은 193 B 상태 26.4만 개입니다. 사용자 수를
  둘 단위를 고르세요.
- 거친 요약은 고운 요약에서 만듭니다(1분 테이블에 연쇄 MV, `uniqMergeState` + 합계). `APPEND`를 쓴
  Refreshable MV는 창이 주기보다 넓으면 설계상 두 번 넣습니다(추론이며 여기서 재현하지 않음).
- 이름은 현지 시각인데 타입은 UTC인 시간 컬럼은 버킷과 TTL을 UTC와의 시차만큼 밀어 놓습니다. 시각은
  시간대를 명시해 저장하세요.
- 소비자(대시보드, MCP의 AI 에이전트, 카탈로그, Kafka Connect 배치)가 많아지면 각자의 사용자와 한도가
  필요합니다. 읽기 전용 사용자에 결과·시간 한도, 적재 쪽은 큰 배치나 async insert.
- 가명 트레이스도 개인정보입니다(아래 "가입자 데이터").

### 가입자 데이터

브론즈에는 벤더가 준 IMSI 해시가 들어 있습니다. 여기서는 시험망 PLMN에 10자리 MSIN을 붙인 값의 키 없는
SHA-256이라, 그 범위의 번호를 모두 대입해 보면 되돌릴 수 있습니다. 실제 환경에서는 키 없는 해시에 기대면
안 됩니다. 실버는 이를 `cityHash64`로 바꾸는데, 이것은 고정된 64비트 가명이지 익명 데이터가 아닙니다.
행마다 격자, 밀리초 시각, 고정 해시가 있으면 가입자 한 명의 이동 경로를 다시 그릴 수 있고, 격자·분 단위
`users`가 1일 수도 있습니다. 가명처리한 데이터도 개인정보입니다(GDPR 전문 26항, 제4조(5)). 운영에서는
레이크 밖에 둔 키로 해시(HMAC)하고 키를 교체하며, 행 단위 단계는 접근을 좁히고 보존 기간을 짧게 두고,
서빙 결과에서는 최소 인원 미만을 가립니다.

### 이 실습이 돌리는 레이어

참조 구조에서 원천 메시지와 표준화는 Kafka와 스트림 처리에 있습니다. 흐름을 한곳에서 보이도록 이
실습은 네 단계를 모두 ClickHouse 안에 두고 Materialized View로 잇습니다.


네 개 모두 `oss_lake` 데이터베이스(Atomic)의 테이블입니다.

| 단계 | 레이어 | 테이블 | 하는 일 | 행 (2시간) |
|---|---|---|---|---:|
| 1 | 단말 | `synth_traces` (매개변수 뷰) | 세 도시에서 1분에 180,000건 | — |
| 2 | 브론즈 | `ue_trace_raw` | 받은 그대로: H3는 문자열, IMSI는 벤더가 준 해시(44자 base64), 모두 Nullable, 일 단위 파티션, TTL 1일(파트째 삭제) | 21,600,000 |
| 3 | 실버 | `ue_trace` ← MV | `stringToH3`, `cityHash64(imsi)`, Float32, `rsrp`만 Nullable. 셀이나 가입자가 없는 행은 버림 | 21,470,291 |
| 4 | 골드 | `cell_kpi_1m` ← MV | AggregatingMergeTree, (분, 셀)마다 한 행: `uniqState(imsi_hash)` + SimpleAggregateFunction 합계 | 2,431,595 |
| 5 | 서빙 | `cell_rank_now` ← Refreshable MV | `REFRESH EVERY 1 MINUTE TO`, `APPEND` 없음: 20행을 한 번에 교체 | 20 |
| 6 | NOC 지도 | — | 20개 셀을 `h3ToGeoBoundary`로 그림, 바탕은 res-7 측정 밀도 | — |

행 수는 2026-10-18 새로 돌린 결과입니다(데이터가 시작 시각으로 시드되므로 실행마다 조금씩 다릅니다).

"지난 1시간"은 `now()`가 아니라 `max(params.anchor_ts)`에서 끝납니다. 그래서 언제 열어도 같은
질문에 답하고, 라이브 데모는 버튼을 누를 때마다 기준 시각을 1분 옮깁니다. **운영 환경에서는
질의와 Refreshable MV가 `now()`를 씁니다.** TTL은 실제로 동작합니다(벽시계 기준). 브론즈와 실버는 1일,
골드는 2일이고, 모두 일 단위 파티션에 `ttl_only_drop_parts = 1`이라 만료된 데이터를 다시 쓰지 않고 파트째
버립니다. 그래서 파티션 하나가 TTL보다 최대 하루 더 남을 수 있습니다. 오래된 컨테이너를 다시 열지 말고
실습을 다시 적재하세요.

### 어느 레이어에서도 같은 답

`03-queries.sql`은 뷰 네 개(`noc_from_bronze`, `_silver`, `_gold`, `_serving`)로 각 레이어에 NOC
질문을 던지고, 서빙을 새로 고친 뒤, 네 레이어가 같은 20행을 돌려주지 않으면 실패합니다(검사 중에 예약된 새로 고침이
서빙을 바꿀 수 있어 먼저 Memory 테이블에 고정해 둡니다). 검사가 실제로 걸리는 것도 확인했습니다. 서빙
한 행을 손으로 바꾸자 `bronze differs from serving`으로 멈췄고, 아래의 잘못된 결과 버그도 이 검사가
잡았습니다(`silver differs from serving`).

레이어별 질의 시간(2026-10-18, 위 기기, 워밍업 1회 뒤 5회 실행 중앙값, 서버 측 `elapsed_ns`, 쿼리
캐시 끔). 참고용이며 벤치마크가 아닙니다.

| 레이어 | 읽은 행 | 시간 |
|---|---:|---:|
| 브론즈 | 10,807,707 | 729 ms |
| 실버 | 10,742,720 | 229 ms |
| 골드 | 1,219,180 | 205 ms |
| 서빙 | 20 | 1.5 ms |

2시간치 생성(`02-generate.sql`)은 16.5초 걸렸습니다. 라이브 데모 버튼 한 번: 브론즈에 180,000행을
넣는 데 0.17–0.23초, 서빙 새로 고침까지 0.42–0.48초(세 번 누름). 그 뒤에도 `/api/q/<n>` 네 개의
답은 같았습니다.

### 만드는 중에 만난 잘못된 결과 (26.6–26.9)

초기의 `tools/hol run` 두 번이 같은 20행 검사에서 실패했습니다. 같은 1시간에 대해 실버가 브론즈보다
몇 행 적게 돌려준 것입니다. 원인(2026-10-18 측정): `DateTime64(3)` 기본 키 컬럼에서
`event_ts < <DateTime 값>` 조건이 키 조건 `event_ts <= <그 값> - 1초`로 바뀝니다
(`< '2026-10-18 08:44:00'`에 대해 `EXPLAIN indexes = 1`이 `event_ts in (-Inf, 1792313039]`를 보여 줌).
마지막 1초 안에서 시작하는 그래뉼(여기서는 `08:43:59.003`, 3,033행)은 건너뛰어져서, 같은 조건의
`countIf`는 세는 행이 `WHERE`에서는 사라집니다. 그래뉼 경계가 어디에 떨어지느냐에 달려 있어 실행마다
나타났다 사라졌습니다.

최소 재현: `DateTime64(3)` 컬럼 하나, `index_granularity = 1000`, 2 ms 간격 5,000행을 **정각에서 3 ms
뒤부터** 넣어 경계 직전 1초 안에서 그래뉼이 시작되게 한 뒤 `WHERE ts < toDateTime('… 00:00:09')`.
26.6.8.7, 26.8.22.13, 26.9.13.15에서 4,499행이 아닌 4,000행을, 25.8.33.6에서는 맞는 값을 돌려줍니다.
행이 정각에서 시작하면 그래뉼도 정각에서 시작해 결과가 맞습니다. 그래서 대충 만든 재현은 통과합니다
(2026-10-18 리뷰에서 26.9.13.15로 다시 확인). 이미 보고된 문제인지는 확인하지 않았습니다.

이 실습은 `event_ts`를 `DateTime64(3)` 경계(`toDateTime64(…, 3)`)와 비교합니다. 그러면 키 조건이
`(-Inf, '1792313040')`이 되고, 버그가 나타났던 실행도 이 변경으로 통과했습니다. 골드의 `bucket`은
`DateTime`을 `DateTime`과 비교하므로 영향이 없습니다.

### 함정 하나: 원본과 더는 맞지 않는 집계 상태

`AggregateFunction` 컬럼의 인자 타입은 Nullable 여부까지 원본 컬럼과 맞아야 합니다.
`pitfall.sql`이 임시 데이터베이스에서 재현합니다(`tools/hol`은 실행하지 않습니다. 일부러 실패합니다).
2026-10-18 측정:

- 서버가 볼 수 있는 불일치는 **CREATE에서** 거부됩니다. `Nullable(Float32)`에 대한 `avgState(rsrp)`를
  `AggregateFunction(avg, Float32)`에 넣는 MV는 25.8.33.6, 26.6.8.7, 26.8.22.13, 26.9.13.15에서 모두
  `CANNOT_CONVERT_TYPE`으로 실패합니다.
- 나중에 생긴 불일치는 거부되지 않습니다. 원본 컬럼이 `Float32`일 때 MV를 만들고,
  `ALTER TABLE … MODIFY COLUMN rsrp Nullable(Float32)`을 실행하면 **성공**하고, 그 뒤 INSERT가 모두
  실패했습니다(26.9.13.15).

  ```
  Code: 70. DB::Exception: Conversion from AggregateFunction(avg, Nullable(Float32)) to
  AggregateFunction(avg, Float32) is not supported: while converting source column avg_rsrp_st to
  destination column avg_rsrp_st: while pushing to view oss_pitfall.kpi_mv … (CANNOT_CONVERT_TYPE)
  ```

  원본 행은 그래도 기록됐습니다(`trace` 2행, `kpi` 1행). 원본은 계속 늘고 집계만 조용히 멈춥니다.

이 실습의 골드 레이어는 rsrp를 단순 합계(`count(rsrp)`, `sum(ifNull(rsrp, 0))`)로 두고 `uniqState`에는
Nullable이 아닌 해시를 넣어 이 함정을 피합니다. 상태 타입을 원본에 맞추는 방법
(`AggregateFunction(avg, Nullable(Float32))`)도 있습니다.

### 파일

| 파일 | 하는 일 |
|---|---|
| `01-schema.sql` | 데이터베이스, `params`, `grid`, 레이어 테이블 네 개, MV 두 개, Refreshable MV, 읽기 전용 사용자 `oss_reader` |
| `02-generate.sql` | 셀 격자(3개 도시 × res-9 셀 6,769개, 도시마다 음영 지역 한 곳), `synth_traces` 뷰, 2시간치 측정 |
| `03-queries.sql` | 레이어별 NOC 질의, `SYSTEM REFRESH VIEW`, 같은 20행 검사 |
| `04-usecases.sql` | 유즈케이스 뷰(분석, 대시보드, 셀별·지역별 알림)와 검사 |
| `05-lessons.sql` | 교훈 검사: 1분 요약에서 이어받은 10분 요약 = 원본(대조군 포함), 지역 요약 합계, 브론즈 행 보존. 타입·서로 다른 값 수·단위별 uniq 상태 크기 |
| `examples/` | 여기서 돌리지 않는 방식: Kafka로 알림 발행, `pg_clickhouse`로 Postgres에서 레이크 읽기 |
| `99-cleanup.sql` | `oss_lake`, `oss_pitfall`, 사용자 삭제 |
| `pitfall.sql` | 위 함정을 손으로 재현 |
| `snapshot.sh` | `site/data/snapshot.json`(행 수, 견본 행, 경계가 붙은 20개 셀, 질의 시간)을 쓰고 페이지를 다시 만듦 |
| `site/` | 설명 페이지(`explainer.html`), 공용 CSS/JS, 카탈로그 `i18n/{ko,en,ja,zh}.json`, `build.py` |
| `ui/server.py` | 표준 라이브러리만 쓰는 서버: `/`에 설명, `/demo`에 데모, 고정 엔드포인트 `/api/layers`, `/api/q/<1-4>`, `/api/map`, `POST /api/tick` |
| `ui/demo.html` | 라이브 데모 페이지(빌드 단계 없음, CDN 없음) |
| `ui/up.sh` | 컨테이너 + 01–05 + 서버를 명령 하나로 |
| `site/data/replay.json` | `ui/server.py --record 6`으로 녹화한 라이브 데모 버튼 6번. ClickHouse가 없는 곳에서 데모가 재생 |
| `vercel.json` | 배포: `python3 site/build.py` → `site/dist`, `api/index.py` 함수, `noindex` 헤더, `/en/` 넘겨주기 |
| `api/index.py` | Vercel 함수: Cloud의 레이크에 대한 데모의 읽기 전용 GET 엔드포인트 |
| `cloud/load.py`, `cloud/feed.sql` | Cloud 서비스에 실습 적재(Cloud 차이 포함), 스스로 도는 흐름, 멈춤 스위치, 삭제 |

### 실행

SQL만, 일회용 컨테이너에서:

```bash
tools/hol run usecase/oss-network-quality-lake
```

ClickHouse 없이 설명 페이지만(커밋된 스냅숏으로 페이지를 만듭니다):

```bash
python3 usecase/oss-network-quality-lake/site/build.py
open usecase/oss-network-quality-lake/site/dist/index.html
```

라이브 데모(Docker와 Python 3. 로컬 전용, Cloud 비용 없음):

```bash
usecase/oss-network-quality-lake/ui/up.sh
```

그다음 <http://localhost:8765/>(설명) 또는 <http://localhost:8765/demo>(데모. 다른 언어는 `/ko/demo`,
`/ja/demo`, `/zh/demo`)를 엽니다. ClickHouse는 `127.0.0.1:18123`에서 듣습니다(`CH_PORT`로 변경).
읽기는 읽기 전용 사용자 `oss_reader`로 하고, 쓰기는 `POST /api/tick` 하나뿐이며 고정된 문장 하나
(`synth_traces`의 다음 1분)만 실행합니다. 페이지에서 보낸 SQL은 실행하지 않습니다. Ctrl-C로 멈추고
`docker rm -f oss-lake-demo`로 컨테이너를 지웁니다.

SQL을 바꾼 뒤에는 적재된 컨테이너를 대상으로 스냅숏을 다시 만듭니다:
`CH_URL=http://localhost:18123 usecase/oss-network-quality-lake/snapshot.sh`.

### ClickHouse Cloud에서 (라이브 사이트)

<https://oss-lake.clickhouse.kr/>는 녹화가 아니라 실제 데이터입니다.

- **레이크**: AWS의 ClickHouse Cloud 서비스에 있는 `oss_lake` 데이터베이스.
  2026-10-18 26.6.1에 `cloud/load.py`로 적재했습니다. 같은 01–05 파일에 docstring에 적은 Cloud
  차이만 더한 것이고, 03–05의 검사는 거기서도 모두 통과했습니다.
- **흐름**: `cloud/feed.sql`이 Refreshable MV 두 개를 더합니다. `feed_rmv`가 1분마다 다음 1분을
  만들고(멈췄다 다시 켜면 한 번에 최대 5분씩 따라잡고, 같은 1분을 두 번 넣지 않음), 이어서
  `anchor_rmv`가 레이크의 '지금'을 옮깁니다. 서빙 새로 고침은 그 뒤에 돕니다. TTL은 `01-schema.sql`에
  있습니다(브론즈·실버 1일, 골드 2일, 파트째 삭제). 그래서 흐름이 멈추지 않아도 레이크 크기가 일정합니다.
  `params`(1분에 1행)에는 걸지 않아, 오래 멈춰도 레이크의 시계가 비지 않습니다.
  `feed start`는 시계가 5분 넘게 뒤처져 있으면 1분 전으로 다시 맞춰, 빈 구간을 다시 만들지 않고
  건너뜁니다. 라이브 데모는 3분 동안 새 1분이 없으면 "멈춤"으로 표시합니다.
- **사이트**: Vercel 프로젝트 `oss-lake`. 페이지는 정적입니다. `api/index.py`가 데모의 GET
  엔드포인트를 읽기 전용 사용자 `oss_reader`로 내줍니다: `readonly = 1`, 20초·읽기 3천만 행·결과 20만 행
  한도, 시간당 쿼터(질의 3,000개, 읽기 50억 행), 엣지 캐시 20초. 엣지 캐시 키가 URL 전체라서, 함수는
  쿼리 문자열을 거부하고(400) 끝의 `/`는 돌려보냅니다(308). 둘 다 ClickHouse를 부르지 않습니다. 오류
  응답은 고정 문구이고 자세한 내용은 함수 로그에만 남습니다. 쓰기 엔드포인트는 없습니다(POST는 405).
  함수가 ClickHouse에 닿지 못하거나 쿼터를 다 쓰면 데모는 녹화한 몇 분으로 돌아갑니다. 모든 엔드포인트는
  범위를 정해 읽습니다: 2026-10-28(2026-10-19부터 feed 상시 가동, bronze에 하루~이틀치)에 `/api/layers`의
  데이터 품질 집계가 bronze 전체를 읽어 1억 3,266만 행에서 3천만 행 한도에 걸렸고, 데모는 녹화본으로
  돌아가 있었습니다. 지금은 최근 1분(18만 행)만 셉니다. 페이지와 함수는
  Content-Security-Policy(`default-src 'self'`, 인라인 스크립트·스타일 허용, `frame-ancestors 'none'`),
  `X-Frame-Options: DENY`, 카메라·마이크·위치·결제·USB를 끈 Permissions-Policy를 함께 보냅니다
  (`vercel.json`).

```bash
cd usecase/oss-network-quality-lake
set -a; . /path/to/your-service.env; set +a   # CH_HOST, CH_USER, CH_PASSWORD (서비스 관리자)
python3 cloud/load.py                 # 적재 (만든 비밀번호는 여기 .env.cloud, 또는 $OSS_LAKE_SECRETS)
python3 cloud/load.py harden          # 2026-10-18 전에 적재한 레이크: 읽기 한도 + 쿼터, params TTL 제거
python3 cloud/load.py feed stop       # 멈춤 스위치. `feed start`로 다시, `feed status`로 확인
python3 cloud/load.py drop            # 데이터베이스와 두 사용자 삭제
vercel deploy --prod --scope litkhai  # 사이트 + 함수 (env: CH_URL, CH_READ_USER, CH_READ_PASSWORD)
```

2026-10-18 그 서비스(복제본 2개, 각 최소 8 GiB, vCPU 2개)에서 측정했습니다.

- 적재 시간: 01은 9초, 02는 66초, 03은 15초, 04는 2초, 05는 12초.
- 흐름은 실패한 새로 고침 없이 1분에 180,000행씩 들어갔고, 레이크의 '지금'은 현재 벽시계 1분
  안에 있었습니다.
- 함수를 거쳐(네트워크 포함) `/api/q/1`(브론즈)은 3.9초, `/api/q/4`(서빙)는 0.35초.
- `oss_reader`로 쓰기를 시도하면 `ACCESS_DENIED`로 거부됐습니다.

만나며 고친 것: 인벤토리 Dictionary는 복제본마다 사본이 따로 있습니다. `SYSTEM RELOAD DICTIONARY`는
한 복제본만 다시 읽었고, 다른 복제본은 인벤토리가 비어 있을 때 읽은 사본을 그대로 들고 있어서 이력
적재의 실버 행이 모두 지역 없이 들어갔습니다. 05의 검사가 이를 잡았습니다. 이제 적재기는
`ON CLUSTER 'default'`로 다시 읽고, 모든 복제본이 인벤토리 전체를 가질 때까지 기다립니다. Dictionary는
5–10분마다 스스로 다시 읽기도 합니다(`LIFETIME(MIN 300 MAX 600)`). 지역 이름은 적재할 때 실버와 골드에
박히므로, 인벤토리를 바꾼 뒤에는 모든 복제본에서 다시 읽고 영향받은 구간을 다시 처리합니다.

05의 검사는 테이블 전체가 아니라 레이크의 '지금' 직전 완결된 1시간만 봅니다. 그래서 층마다 TTL이 달라도
적재하고 며칠 뒤에 다시 돌려도 맞습니다. 그 1시간이 끊기지 않았다고 가정하므로, `feed start`가 빈 구간을
건너뛴 직후라면 1시간 뒤에 다시 돌립니다. 브론즈 검사는 일부가 빠지거나 겹친 분뿐 아니라 통째로 빠진 분도
잡습니다(2026-10-18 로컬 레이크에서 1분을 지워 "bronze is missing a minute"를 확인).

비용 (2026-10-18 추정):

- 이 서비스는 이미 상시 실행 중이라(유휴 축소 꺼짐) 기본 컴퓨트는 이 실습 때문에 생긴 비용이 아닙니다.
- 처음 TTL(원본 3일, 골드 7일) 기준 2026-10-18 추정: 일일 백업 하나를 포함한 저장 약 0.11 TB. 서비스 리전의
  공시 요금 TB·월 $27.50(2026-10-18 확인)으로 월 약 $3이고, 여기에 1분에 약 1초인 흐름의 CPU가 붙습니다.
- 지금 TTL(1일, 골드 2일) 기준 2026-10-19 다시 추정: 2026-10-18 22:34 UTC Cloud 레이크의 2시간치 크기를
  선형으로 늘린 값입니다(정착 상태에서 잰 값 아님). 브론즈 약 11 GB, 실버 4.2 GB, 골드 1분 2.3 GB, 지역
  1.9 GB, 10분 1.4 GB, 모두 약 21 GB입니다. 일일 백업까지 대략 두 배라 같은 요금으로 월 약 $1.2입니다.
- 나중에 유휴 축소를 켜면 흐름이 서비스를 계속 깨워 둡니다. 그 전에 흐름을 멈추세요.

### 언어

한국어가 원본입니다. `site/i18n/{ko,en,ja,zh}.json`은 언어마다 카탈로그 하나이며 설명 페이지와 데모가
함께 씁니다. `build.py`는 `/`(en), `/ko/`, `/ja/`, `/zh/`를 쓰고, 키 집합이 다르면 실패합니다
(확인: `ja.json`에서 `cta.note`를 빼자 `ja.json: missing ['cta.note']`로 멈춤). SQL, 테이블과 컬럼
이름은 번역하지 않습니다. 2026-10-18 브라우저에서 320px과 데스크톱 너비, 라이트와 다크, 네 언어
모두 확인했습니다.

### 다루지 않는 것

- 규모: 2시간, 셀 약 2만 개. 크기가 아니라 흐름이 목적입니다.
- 실제 probe 형식, 실제 IMSI 암호화, Kafka나 오브젝트 스토리지 적재: 브론즈는 SQL로 채웁니다.
- 노트 사이트 게시(`web`을 설정하지 않음).

### 작성자

Ken Lee (ClickHouse SA) · License: MIT
