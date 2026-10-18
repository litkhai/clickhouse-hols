# OSS network-quality lake — one measurement from a phone to the NOC map

[English](#english) | [한국어](#한국어)

---

## English

A telco **OSS** (operations: equipment, faults, quality; not BSS, which is billing) receives
measurement traces from phones. A NOC screen needs, for the last hour, the 10 H3 res-9 cells with
the most users and the 10 with the weakest signal. This lab builds that as four ClickHouse layers
and follows one measurement through them, so the flow of data is visible: what each layer changes,
and how the row count shrinks from millions to the 20 rows the screen reads.

It is made to be shown: a static explainer page (works without ClickHouse) and a local live demo
with a "send next minute" button, both in Korean, English, Japanese and Chinese. Performance numbers
are a supporting line, not the point.

The operator and the three cities are fictional; only the city-centre coordinates (Seoul, Busan,
Daegu) are real. All data is generated in SQL. IMSIs use the test network code 001-01.

**Verified on ClickHouse 26.9.13.15** (`clickhouse/clickhouse-server:26.9.13.15`), 2026-10-18:
`tools/hol run usecase/oss-network-quality-lake` passes (01–99, about 26 s; three runs in a row after the fix below), and the live demo was run
with `ui/up.sh` and its button pressed several times. Machine: Apple M4 Pro, macOS, Docker Desktop;
the container sees 12 CPUs and 7.75 GiB.

### The layers

All four are tables in database `oss_lake` (Atomic).

| Step | Layer | Table | What happens | Rows (2 h) |
|---|---|---|---|---:|
| 1 | phone | `synth_traces` (parameterized view) | 180,000 measurements a minute across three cities | — |
| 2 | bronze | `ue_trace_raw` | kept as received: H3 as a string, IMSI as 44-char base64 ciphertext, everything Nullable, daily partition, TTL 3 days | 21,600,000 |
| 3 | silver | `ue_trace` ← MV | `stringToH3`, `cityHash64(imsi)`, Float32, only `rsrp` stays Nullable; rows without a cell or a subscriber are dropped | 21,470,291 |
| 4 | gold | `cell_kpi_1m` ← MV | AggregatingMergeTree, one row per (minute, cell): `uniqState(imsi_hash)` + SimpleAggregateFunction sums | 2,431,595 |
| 5 | serving | `cell_rank_now` ← refreshable MV | `REFRESH EVERY 1 MINUTE TO`, no `APPEND`: the 20 rows, replaced in one swap | 20 |
| 6 | NOC map | — | the 20 cells drawn from `h3ToGeoBoundary`, on a res-7 density background | — |

Row counts measured 2026-10-18 on a fresh run (they move slightly between runs because the data is
seeded from the start minute).

"The last hour" ends at `max(params.anchor_ts)`, not `now()`, so the lab still answers the question
whenever it is opened; the live feed moves the anchor one minute per press. **In production the
queries and the refreshable MV would use `now()`.** Bronze's TTL is real: data older than 3 days
(wall clock) is removed, so reload the lab rather than reopening an old container.

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

A minimal reproduction (one `DateTime64(3)` column, `index_granularity = 1000`, 5,000 rows 2 ms apart,
`WHERE ts < toDateTime('… 00:00:09')`) returns 4,000 rows instead of 4,500 on 26.6.8.7, 26.8.22.13
and 26.9.13.15, and the correct 4,500 on 25.8.33.6. Whether it is already reported upstream was not
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
| `99-cleanup.sql` | drops `oss_lake`, `oss_pitfall` and the user |
| `pitfall.sql` | the pitfall above, by hand |
| `snapshot.sh` | writes `site/data/snapshot.json` (counts, sample rows, the 20 cells with boundaries, query times) and rebuilds the pages |
| `site/` | explainer (`explainer.html`), shared CSS/JS, catalogues `i18n/{ko,en,ja,zh}.json`, `build.py` |
| `ui/server.py` | stdlib-only server: explainer at `/`, demo at `/demo`, fixed endpoints `/api/layers`, `/api/q/<1-4>`, `/api/map`, `POST /api/tick` |
| `ui/demo.html` | the live demo page (no build step, no CDN) |
| `ui/up.sh` | container + 01–03 + server, in one command |

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

Then open <http://localhost:8765/> (explainer) or <http://localhost:8765/demo> (demo; `/en/demo`,
`/ja/demo`, `/zh/demo` for the other languages). ClickHouse listens on `127.0.0.1:18123`
(`CH_PORT` to change). Reads go through the read-only user `oss_reader`; only `POST /api/tick`
writes, and it runs one fixed statement (the next minute from `synth_traces`), never SQL from the
page. Stop with Ctrl-C and remove the container with `docker rm -f oss-lake-demo`.

After changing the SQL, refresh the snapshot against a loaded container:
`CH_URL=http://localhost:18123 usecase/oss-network-quality-lake/snapshot.sh`.

### Languages

Korean is the source. `site/i18n/{ko,en,ja,zh}.json` is one catalogue per language, shared by the
explainer and the demo; `build.py` writes `/` (ko), `/en/`, `/ja/`, `/zh/` and fails when the key
sets differ (seen: removing `cta.note` from `ja.json` stopped the build with
`ja.json: missing ['cta.note']`). SQL, table and column names are not translated. Checked in the
browser on 2026-10-18 at 320 px and desktop width, light and dark, in all four languages.

### Not covered

- ClickHouse Cloud (not run; it costs money).
- Scale: two hours, about 20k cells. The point is the flow, not the size.
- Real probe formats, real IMSI encryption, Kafka or object-storage ingestion: bronze is filled by SQL.
- Publishing to the notes site (`web` is not set).

### Author

Ken Lee (ClickHouse SA) · License: MIT

---

## 한국어

통신사 **OSS**(운영: 장비, 장애, 품질. 요금·청구를 다루는 BSS가 아님)는 휴대폰의 측정 기록을
받습니다. NOC 화면은 지난 1시간 동안 사용자가 가장 많은 H3 res-9 셀 10개와 신호가 가장 약한 셀
10개를 보여 줘야 합니다. 이 실습은 그것을 ClickHouse 레이어 네 개로 만들고, 측정 한 건이 그
레이어들을 지나가는 모습을 따라갑니다. 레이어마다 무엇이 바뀌는지, 행 수가 수백만에서 화면이 읽는
20행까지 어떻게 줄어드는지가 보이도록 했습니다.

보여 주기 위한 실습입니다. 정적인 설명 페이지(ClickHouse 없이 열림)와 "다음 1분 보내기" 버튼이
있는 로컬 라이브 데모를 한국어, 영어, 일본어, 중국어로 제공합니다. 성능 수치는 보조 정보입니다.

통신사와 세 도시는 가상이고, 도시 중심 좌표(서울, 부산, 대구)만 실제입니다. 데이터는 모두 SQL로
만듭니다. IMSI는 시험망 코드 001-01을 씁니다.

**ClickHouse 26.9.13.15에서 검증** (`clickhouse/clickhouse-server:26.9.13.15`), 2026-10-18:
`tools/hol run usecase/oss-network-quality-lake` 통과(01–99, 약 26초. 아래 우회 뒤 연속 세 번). 라이브 데모는 `ui/up.sh`로
띄워 버튼을 여러 번 눌러 확인했습니다. 기기: Apple M4 Pro, macOS, Docker Desktop, 컨테이너는
CPU 12개와 7.75 GiB를 봅니다.

### 레이어

네 개 모두 `oss_lake` 데이터베이스(Atomic)의 테이블입니다.

| 단계 | 레이어 | 테이블 | 하는 일 | 행 (2시간) |
|---|---|---|---|---:|
| 1 | 휴대폰 | `synth_traces` (매개변수 뷰) | 세 도시에서 1분에 180,000건 | — |
| 2 | 브론즈 | `ue_trace_raw` | 받은 그대로: H3는 문자열, IMSI는 44자 base64 암호문, 모두 Nullable, 일 단위 파티션, TTL 3일 | 21,600,000 |
| 3 | 실버 | `ue_trace` ← MV | `stringToH3`, `cityHash64(imsi)`, Float32, `rsrp`만 Nullable. 셀이나 가입자가 없는 행은 버림 | 21,470,291 |
| 4 | 골드 | `cell_kpi_1m` ← MV | AggregatingMergeTree, (분, 셀)마다 한 행: `uniqState(imsi_hash)` + SimpleAggregateFunction 합계 | 2,431,595 |
| 5 | 서빙 | `cell_rank_now` ← Refreshable MV | `REFRESH EVERY 1 MINUTE TO`, `APPEND` 없음: 20행을 한 번에 교체 | 20 |
| 6 | NOC 지도 | — | 20개 셀을 `h3ToGeoBoundary`로 그림, 바탕은 res-7 측정 밀도 | — |

행 수는 2026-10-18 새로 돌린 결과입니다(데이터가 시작 시각으로 시드되므로 실행마다 조금씩 다릅니다).

"지난 1시간"은 `now()`가 아니라 `max(params.anchor_ts)`에서 끝납니다. 그래서 언제 열어도 같은
질문에 답하고, 라이브 데모는 버튼을 누를 때마다 기준 시각을 1분 옮깁니다. **운영 환경에서는
질의와 Refreshable MV가 `now()`를 씁니다.** 브론즈의 TTL은 실제로 동작합니다. 3일(벽시계 기준)이
지난 데이터는 지워지므로, 오래된 컨테이너를 다시 열지 말고 실습을 다시 적재하세요.

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

최소 재현(`DateTime64(3)` 컬럼 하나, `index_granularity = 1000`, 2 ms 간격 5,000행,
`WHERE ts < toDateTime('… 00:00:09')`)은 26.6.8.7, 26.8.22.13, 26.9.13.15에서 4,500행이 아닌 4,000행을,
25.8.33.6에서는 맞는 4,500행을 돌려줍니다. 이미 보고된 문제인지는 확인하지 않았습니다.

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
| `99-cleanup.sql` | `oss_lake`, `oss_pitfall`, 사용자 삭제 |
| `pitfall.sql` | 위 함정을 손으로 재현 |
| `snapshot.sh` | `site/data/snapshot.json`(행 수, 견본 행, 경계가 붙은 20개 셀, 질의 시간)을 쓰고 페이지를 다시 만듦 |
| `site/` | 설명 페이지(`explainer.html`), 공용 CSS/JS, 카탈로그 `i18n/{ko,en,ja,zh}.json`, `build.py` |
| `ui/server.py` | 표준 라이브러리만 쓰는 서버: `/`에 설명, `/demo`에 데모, 고정 엔드포인트 `/api/layers`, `/api/q/<1-4>`, `/api/map`, `POST /api/tick` |
| `ui/demo.html` | 라이브 데모 페이지(빌드 단계 없음, CDN 없음) |
| `ui/up.sh` | 컨테이너 + 01–03 + 서버를 명령 하나로 |

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

그다음 <http://localhost:8765/>(설명) 또는 <http://localhost:8765/demo>(데모. 다른 언어는 `/en/demo`,
`/ja/demo`, `/zh/demo`)를 엽니다. ClickHouse는 `127.0.0.1:18123`에서 듣습니다(`CH_PORT`로 변경).
읽기는 읽기 전용 사용자 `oss_reader`로 하고, 쓰기는 `POST /api/tick` 하나뿐이며 고정된 문장 하나
(`synth_traces`의 다음 1분)만 실행합니다. 페이지에서 보낸 SQL은 실행하지 않습니다. Ctrl-C로 멈추고
`docker rm -f oss-lake-demo`로 컨테이너를 지웁니다.

SQL을 바꾼 뒤에는 적재된 컨테이너를 대상으로 스냅숏을 다시 만듭니다:
`CH_URL=http://localhost:18123 usecase/oss-network-quality-lake/snapshot.sh`.

### 언어

한국어가 원본입니다. `site/i18n/{ko,en,ja,zh}.json`은 언어마다 카탈로그 하나이며 설명 페이지와 데모가
함께 씁니다. `build.py`는 `/`(ko), `/en/`, `/ja/`, `/zh/`를 쓰고, 키 집합이 다르면 실패합니다
(확인: `ja.json`에서 `cta.note`를 빼자 `ja.json: missing ['cta.note']`로 멈춤). SQL, 테이블과 컬럼
이름은 번역하지 않습니다. 2026-10-18 브라우저에서 320px과 데스크톱 너비, 라이트와 다크, 네 언어
모두 확인했습니다.

### 다루지 않는 것

- ClickHouse Cloud(비용이 들어 실행하지 않음).
- 규모: 2시간, 셀 약 2만 개. 크기가 아니라 흐름이 목적입니다.
- 실제 probe 형식, 실제 IMSI 암호화, Kafka나 오브젝트 스토리지 적재: 브론즈는 SQL로 채웁니다.
- 노트 사이트 게시(`web`을 설정하지 않음).

### 작성자

Ken Lee (ClickHouse SA) · License: MIT
