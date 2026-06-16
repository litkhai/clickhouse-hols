# Ad Performance Analytics Cube with ClickHouse

[English](#english) | [한국어](#한국어)

---

## English

A hands-on, end-to-end laboratory for building an **ad-performance analytics "cube"** on ClickHouse. It models a generic digital advertising platform (ad network / retail media / DSP·SSP / in-house ad server) where bid telemetry, ML ranking signals, and business KPIs all land in **one wide append-only event row**, and analysts want to slice it by **arbitrary dimensions in near real time**.

Built around a synthetic **10 million-row `ad_events` stream**, it walks through every primitive that makes ClickHouse a natural fit for this workload: conditional aggregation (`countIf`/`sumIf`/`avgIf`), approximate distinct counts (`uniq`/`uniqCombined`), semi-structured JSON parsing, in-memory dictionary enrichment (`dictGet`), quantile distributions, and real-time roll-ups via `AggregatingMergeTree` + Materialized Views.

### 🎯 Why this lab

A digital advertising platform commonly handles three concerns from one event stream:

1. **Ad serving & auction (RTB) telemetry** — bid requests, candidate ranking, win price, served rank
2. **ML ranking signals** — predicted CTR/CVR (pCTR·pCTCVR), quality score, capping behavior
3. **Business reporting** — spend, revenue, ROAS sliced by any dimension combination

The combination of *"high-frequency append-only stream + arbitrary-dimension OLAP aggregation + approximate distinct + semi-structured enrichment"* is the textbook ClickHouse sweet spot. This lab makes that fit concrete and measurable.

### 📊 Dataset

A synthetic generic ad platform:
- **Events**: 10,000,000 (30 days, 2026-05-15 → 2026-06-13)
- **Funnel**: IMPRESSION 85% · VIEWABLE_IMPRESSION 8% · CLICK 3.5% · INTERACTION 1.5% · DIRECT_CONVERSION 1.2% · INDIRECT_CONVERSION 0.8% → realistic CTR ≈ 4%, CVR ≈ 57%
- **Wide schema**: ~50 dimensions per row (ad hierarchy L1–L4, inventory, user/device, RTB, ML signals, 3 JSON fields)
- **Campaigns**: 500 (fed into an in-memory dictionary)
- **High cardinality**: ~1.9M users, ~2.9M devices, ~5M bid requests
- Money fields are **scaled integers** (micro-units, `SCALE = 1,000,000`); scale factor & take rates live in a `cube_params` table, never hard-coded

### 📁 File Structure

```
ads-analytics/
├── README.md                  # This file
├── 01-schema.sql              # ad_events wide table + campaign_dict + cube_params
├── 02-load.sql                # 10M synthetic events + 500 campaigns (hashed funnel)
├── 03-cube-basics.sql         # countIf/sumIf cube: CTR/CVR/CTCVR/CPC/CPM/ROAS/Profit
├── 04-approx-distinct.sql     # uniq vs uniqExact, DAU, reach, frequency capping
├── 05-json-enrichment.sql     # JSONExtract*, dictGet, MATERIALIZED column promotion
├── 06-model-ranking.sql       # quantile distributions, pCTR–CTR gap, capping ratios
├── 07-materialized-views.sql  # AggregatingMergeTree daily cube + live-insert test
└── 99-cleanup.sql             # Drop everything
```

### 🚀 Quick Start

```bash
cd usecase/ads-analytics

# Against a running ClickHouse (server or `clickhouse local`)
for f in 01-schema.sql 02-load.sql 03-cube-basics.sql \
         04-approx-distinct.sql 05-json-enrichment.sql \
         06-model-ranking.sql 07-materialized-views.sql; do
    echo "▶ Running $f"
    clickhouse-client --multiquery --queries-file "$f"
done
```

Or with a stateless `clickhouse local` (persisting to a local path):

```bash
for f in 01-schema.sql 02-load.sql 03-cube-basics.sql \
         04-approx-distinct.sql 05-json-enrichment.sql \
         06-model-ranking.sql 07-materialized-views.sql; do
    clickhouse local --path /tmp/ad_cube --multiquery --queries-file "$f"
done
```

### 📖 Lab Walkthrough

#### 01 — Schema ([01-schema.sql](01-schema.sql))

Creates the `ad_analytics` database and four objects:
- **`ad_events`** — the single wide event table. `ORDER BY (channelType, campaignId, eventType, eventTs)` puts the most common filter/group columns first; `PARTITION BY toYYYYMM(eventTs)` enables date pruning. Enum-like columns use `LowCardinality(String)`; money is `Int64` (scaled).
- **`campaign_meta`** — small dimension table (500 rows) that feeds the dictionary.
- **`campaign_dict`** — `COMPLEX_KEY_HASHED` dictionary over `campaign_meta` for JOIN-free `dictGet()`.
- **`cube_params`** — `SCALE` and take rates as data, so measure expressions stay parameter-driven.

#### 02 — Synthetic data ([02-load.sql](02-load.sql))

10M events generated from `numbers(10000000)`, every field hashed deterministically from `number` via `cityHash64(number, 'salt')`. The funnel stage is picked from a 0–999 bucket; `winPrice` is populated only on CLICK rows, `conversionValue` only on conversion rows, so the downstream `sumIf` measures behave realistically.

#### 03 — The cube ([03-cube-basics.sql](03-cube-basics.sql))

The heart of the lab. Every funnel metric is a **conditional aggregate over the same table in a single pass**:

```sql
countIf(eventType = 'CLICK') * 100.0
  / nullIf(countIf(eventType = 'IMPRESSION'), 0)   AS ctr_pct
```

Covers Impression/Click/Conversion counts, Spending/Revenue/Profit, and CTR/CVR/CTCVR/CPC/CPM/ROAS — then re-slices the *same* cube by `channel × platform`, by `campaignGoal`, and by day. **No new table, no new index — just change the `GROUP BY`.** `SCALE` and take rates are pulled from `cube_params` as scalar subqueries.

> **Scale rule:** ratio KPIs (CTR, ROAS) cancel the scale factor, so no `/SCALE`. Absolute-money KPIs (CPC, CPM, Spending) *do* divide by `SCALE`.

#### 04 — Approximate distinct ([04-approx-distinct.sql](04-approx-distinct.sql))

`userId`/`deviceId`/`requestId` have millions of distinct values:

| Function | Use | Error (measured) |
|---|---|---|
| `uniqExact` | billing / settlement | 0% (exact, heaviest) |
| `uniq` | dashboards (default) | ~0.15% |
| `uniqCombined` | tunable accuracy/memory | ~0.35% |

Plus DAU, `uniqIf` (distinct only over a sub-population — "campaigns that actually got an impression"), reach-per-line-item, per-user economics, and a frequency-capping distribution (impressions per user).

> **Rule of thumb:** approximate distinct for exploration & dashboards; `uniqExact` only where a number drives money (billing/settlement).

#### 05 — JSON & dictionary enrichment ([05-json-enrichment.sql](05-json-enrichment.sql))

Two ways to enrich the wide table without JOINs:
- **`JSONExtract*`** on the `creativeAsset` / `biddingStrategy` / `experiment` String columns — including nested paths (`JSONExtractString(creativeAsset, 'item', 'id')`) and typed numeric parsing.
- **`dictGet()`** on `campaign_dict` — resolves campaign name/status/targetRoas per row from RAM, then compares actual vs target ROAS for pacing.

Finally, promotes a hot JSON path to a **`MATERIALIZED` column** (`ALTER TABLE … ADD COLUMN … MATERIALIZED` + `MATERIALIZE COLUMN` backfill) so future reads scan a `LowCardinality` column instead of re-parsing JSON.

#### 06 — ML ranking quality ([06-model-ranking.sql](06-model-ranking.sql))

Mixes conditional aggregates with `quantile` distributions on the model-signal columns:
- Score distributions (avg / median / p95 / p99 of `rawPCtr`)
- **Calibration gap** — `avg(pCTR) − actual CTR` per channel
- **Capping ratios** — lower / higher / total adjustment of `qualityScore` vs `rawQualityScore`
- Rank movement (`candidateRank` → `rank`) and an eCPM-style `quality × bid` ranking score

#### 07 — Real-time pre-aggregation ([07-materialized-views.sql](07-materialized-views.sql))

A daily `(campaign, eventType)` cube in an `AggregatingMergeTree`, fed by a Materialized View:

```sql
CREATE TABLE daily_campaign_cube (
    reportDate Date, campaignId String, eventType LowCardinality(String),
    events     AggregateFunction(count),
    spend_raw  AggregateFunction(sum, Int64),
    users      AggregateFunction(uniq, Nullable(String))
) ENGINE = AggregatingMergeTree() ORDER BY (reportDate, campaignId, eventType);
```

Reads use `countMerge`/`sumMerge`/`uniqMerge` (and the `*MergeIf` combinator to split metrics by `eventType` in one query). The aggregate gives the **same numbers** as the raw scan (verified: 349,540 clicks / 307,367.09 spend from both), and a live-INSERT test proves the MV auto-rolls-up new events.

### 🔑 Gotchas worth remembering

| | Note |
|---|---|
| **Scaled-integer money** | Store currency as `Int64` micro-units to avoid float drift. Divide by `SCALE` only for absolute-money KPIs; ratio KPIs cancel it out. |
| **Parameterize, don't hard-code** | `SCALE`, take rates, tokenizer choices → a params table, read as scalar subqueries. Contract/model changes never touch query SQL. |
| **MATERIALIZED columns aren't INSERTed** | Omit them from explicit `INSERT` column lists — they are computed. `ADD COLUMN … MATERIALIZED` does not backfill old parts until you run `MATERIALIZE COLUMN`. |
| **`*State` ↔ `*Merge` must pair** | An `AggregateFunction(uniq, …)` column written with `uniqState` is read with `uniqMerge`. The `*MergeIf` combinator filters during the merge. |
| **Approximate vs exact distinct** | `uniq` is HyperLogLog (~1% error, tiny memory); reserve `uniqExact` for billing. |
| **`numbers(N)` not `system.numbers`** | `numbers(N)` terminates; `system.numbers` is infinite. |

### 🔍 Additional resources

- [ClickHouse aggregate functions](https://clickhouse.com/docs/sql-reference/aggregate-functions)
- [Combinators (`-If`, `-State`, `-Merge`)](https://clickhouse.com/docs/sql-reference/aggregate-functions/combinators)
- [JSON functions](https://clickhouse.com/docs/sql-reference/functions/json-functions)
- [Dictionaries](https://clickhouse.com/docs/sql-reference/dictionaries)
- [Materialized Views](https://clickhouse.com/docs/materialized-view)

### 📝 Verification

All scripts verified end-to-end against **ClickHouse 26.6.1.778** from an empty state (`clickhouse local`):

| Script | Output lines | Errors |
|---|---|---|
| `01-schema.sql` | 5 | 0 |
| `02-load.sql` | 10 | 0 |
| `03-cube-basics.sql` | 37 | 0 |
| `04-approx-distinct.sql` | 31 | 0 |
| `05-json-enrichment.sql` | 29 | 0 |
| `06-model-ranking.sql` | 16 | 0 |
| `07-materialized-views.sql` | 15 | 0 |

### 📝 License

MIT License

### 👤 Author

Ken Lee (ClickHouse Solution Architect) — ken.lee@clickhouse.com
Created: 2026-06-16

---

**Happy Cubing! 📊**

For questions, see the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse로 **광고 성과 분석 "큐브"**를 구축하는 종단간 실습 환경입니다. 디지털 광고 플랫폼(애드 네트워크 / 리테일 미디어 / DSP·SSP / 인하우스 광고 서버) 일반을 모델링하며, 입찰 텔레메트리 + ML 랭킹 신호 + 비즈니스 KPI가 모두 **하나의 넓은 append-only 이벤트 row**에 기록되고, 분석가가 **임의 차원으로 거의 실시간에 가깝게 집계**하기를 원하는 상황을 다룹니다.

합성된 **1,000만 행 `ad_events` 스트림**을 기반으로, 이 워크로드에 ClickHouse가 자연스럽게 들어맞게 만드는 기능 전반 — 조건부 집계(`countIf`/`sumIf`/`avgIf`), 근사 고유값 카운트(`uniq`/`uniqCombined`), 반정형 JSON 파싱, 인메모리 사전 enrichment(`dictGet`), quantile 분포, `AggregatingMergeTree` + Materialized View 실시간 롤업 — 을 모두 다룹니다.

### 🎯 왜 이 랩인가

디지털 광고 플랫폼은 보통 하나의 이벤트 흐름에서 세 가지 관심사를 다룹니다.

1. **광고 서빙 & 경매(RTB) 텔레메트리** — 입찰 요청, 후보 랭킹, 낙찰가, 노출 순위
2. **ML 랭킹 신호** — 예측 CTR/CVR(pCTR·pCTCVR), 품질 점수, 캡핑 동작
3. **비즈니스 리포팅** — 소진액·매출·ROAS를 임의 차원 조합으로 슬라이스

*"고빈도 append 스트림 + 임의 차원 OLAP 집계 + 근사 distinct + 반정형 enrichment"* 의 조합은 ClickHouse의 전형적인 강점 영역입니다. 본 랩은 그 적합성을 구체적이고 측정 가능하게 보여줍니다.

### 📊 데이터셋

합성 광고 플랫폼:
- **이벤트**: 10,000,000건 (30일, 2026-05-15 → 2026-06-13)
- **퍼널**: 노출 85% · 뷰어블 8% · 클릭 3.5% · 인터랙션 1.5% · 직접전환 1.2% · 간접전환 0.8% → 현실적인 CTR ≈ 4%, CVR ≈ 57%
- **와이드 스키마**: 행당 약 50개 차원 (광고 계층 L1–L4, 인벤토리, 사용자/디바이스, RTB, ML 신호, JSON 3종)
- **캠페인**: 500개 (인메모리 사전에 적재)
- **고카디널리티**: 사용자 약 190만, 디바이스 약 290만, 입찰 요청 약 500만
- 금액 필드는 **scaled integer** (마이크로 단위, `SCALE = 1,000,000`); 스케일 팩터·수수료율은 `cube_params` 테이블에 두고 하드코딩하지 않음

### 📁 파일 구조

```
ads-analytics/
├── README.md                  # 이 문서
├── 01-schema.sql              # ad_events 와이드 테이블 + campaign_dict + cube_params
├── 02-load.sql                # 1,000만 합성 이벤트 + 500 캠페인 (해시 퍼널)
├── 03-cube-basics.sql         # countIf/sumIf 큐브: CTR/CVR/CTCVR/CPC/CPM/ROAS/Profit
├── 04-approx-distinct.sql     # uniq vs uniqExact, DAU, 도달, 프리퀀시 캡
├── 05-json-enrichment.sql     # JSONExtract*, dictGet, MATERIALIZED 컬럼 승격
├── 06-model-ranking.sql       # quantile 분포, pCTR–CTR 갭, 캡핑 비율
├── 07-materialized-views.sql  # AggregatingMergeTree 일별 큐브 + 라이브 INSERT 테스트
└── 99-cleanup.sql             # 모든 객체 삭제
```

### 🚀 빠른 시작

```bash
cd usecase/ads-analytics

# 실행 중인 ClickHouse (서버 또는 `clickhouse local`)에 대해
for f in 01-schema.sql 02-load.sql 03-cube-basics.sql \
         04-approx-distinct.sql 05-json-enrichment.sql \
         06-model-ranking.sql 07-materialized-views.sql; do
    echo "▶ Running $f"
    clickhouse-client --multiquery --queries-file "$f"
done
```

상태 비저장 `clickhouse local`(로컬 경로에 영속화)로 실행하려면:

```bash
for f in 01-schema.sql 02-load.sql 03-cube-basics.sql \
         04-approx-distinct.sql 05-json-enrichment.sql \
         06-model-ranking.sql 07-materialized-views.sql; do
    clickhouse local --path /tmp/ad_cube --multiquery --queries-file "$f"
done
```

### 📖 랩 워크스루

#### 01 — 스키마

`ad_analytics` 데이터베이스와 네 개의 객체를 생성:
- **`ad_events`** — 단일 와이드 이벤트 테이블. `ORDER BY (channelType, campaignId, eventType, eventTs)`로 가장 빈번한 필터/그룹 컬럼을 앞에 두고, `PARTITION BY toYYYYMM(eventTs)`로 날짜 프루닝. enum성 컬럼은 `LowCardinality(String)`, 금액은 `Int64`(scaled).
- **`campaign_meta`** — 사전의 소스가 되는 작은 차원 테이블 (500행).
- **`campaign_dict`** — `campaign_meta` 위의 `COMPLEX_KEY_HASHED` 사전, JOIN 없는 `dictGet()`용.
- **`cube_params`** — `SCALE`과 수수료율을 데이터로 보관해 지표 표현식을 파라미터 기반으로 유지.

#### 02 — 합성 데이터

`numbers(10000000)`에서 1,000만 이벤트 생성. 모든 필드는 `cityHash64(number, 'salt')`로 `number`에서 결정적으로 해시. 퍼널 단계는 0–999 버킷에서 선택하고, `winPrice`는 CLICK 행에만, `conversionValue`는 전환 행에만 채워 downstream `sumIf` 지표가 현실적으로 동작.

#### 03 — 큐브

랩의 핵심. 모든 퍼널 지표는 **동일 테이블에 대한 단일 패스 조건부 집계**:

```sql
countIf(eventType = 'CLICK') * 100.0
  / nullIf(countIf(eventType = 'IMPRESSION'), 0)   AS ctr_pct
```

노출/클릭/전환 카운트, 소진액/매출/Profit, CTR/CVR/CTCVR/CPC/CPM/ROAS를 다룬 뒤, *동일한* 큐브를 `채널 × 플랫폼`, `campaignGoal`, 일별로 다시 슬라이스. **새 테이블도 새 인덱스도 필요 없이 `GROUP BY`만 변경.** `SCALE`과 수수료율은 `cube_params`에서 스칼라 서브쿼리로 주입.

> **스케일 규칙:** 비율 KPI(CTR, ROAS)는 스케일이 상쇄되므로 `/SCALE` 불필요. 절대 금액 KPI(CPC, CPM, Spending)에만 `/SCALE` 적용.

#### 04 — 근사 고유값

`userId`/`deviceId`/`requestId`는 distinct 수가 수백만:

| 함수 | 용도 | 오차 (측정값) |
|---|---|---|
| `uniqExact` | 정산 / 과금 | 0% (정확, 가장 무거움) |
| `uniq` | 대시보드 (기본) | ~0.15% |
| `uniqCombined` | 정확도/메모리 조정 | ~0.35% |

추가로 DAU, `uniqIf`(부분집합 distinct — "실제 노출이 발생한 캠페인"), 라인아이템당 도달, 사용자 단위 경제성, 프리퀀시 캡 분포(사용자당 노출 수).

> **원칙:** 탐색·대시보드는 근사 distinct; 금액에 직결되는 수치(과금/정산)에만 `uniqExact`.

#### 05 — JSON & 사전 Enrichment

와이드 테이블을 JOIN 없이 enrich하는 두 방법:
- **`JSONExtract*`** — `creativeAsset` / `biddingStrategy` / `experiment` String 컬럼에 대해 중첩 경로(`JSONExtractString(creativeAsset, 'item', 'id')`)와 타입 숫자 파싱.
- **`dictGet()`** — `campaign_dict`에서 캠페인 name/status/targetRoas를 RAM에서 행별로 해결한 뒤, 실제 ROAS vs 목표 ROAS 페이싱 비교.

마지막으로 핫한 JSON 경로를 **`MATERIALIZED` 컬럼**으로 승격(`ALTER TABLE … ADD COLUMN … MATERIALIZED` + `MATERIALIZE COLUMN` 백필)해 이후 읽기가 JSON 재파싱 없이 `LowCardinality` 컬럼만 스캔하도록 함.

#### 06 — ML 랭킹 품질

모델 신호 컬럼에 조건부 집계와 `quantile` 분포를 결합:
- 점수 분포 (`rawPCtr`의 avg / median / p95 / p99)
- **보정 갭** — 채널별 `avg(pCTR) − 실제 CTR`
- **캡핑 비율** — `qualityScore` vs `rawQualityScore`의 하향/상향/전체 조정
- 랭크 이동(`candidateRank` → `rank`)과 eCPM 스타일 `품질 × 입찰가` 랭킹 점수

#### 07 — 실시간 사전 집계

Materialized View가 채우는 `AggregatingMergeTree`의 일별 `(campaign, eventType)` 큐브:

```sql
CREATE TABLE daily_campaign_cube (
    reportDate Date, campaignId String, eventType LowCardinality(String),
    events     AggregateFunction(count),
    spend_raw  AggregateFunction(sum, Int64),
    users      AggregateFunction(uniq, Nullable(String))
) ENGINE = AggregatingMergeTree() ORDER BY (reportDate, campaignId, eventType);
```

읽기는 `countMerge`/`sumMerge`/`uniqMerge`(그리고 한 쿼리에서 `eventType`별로 지표를 나누는 `*MergeIf` 콤비네이터)로 처리. 집계 테이블은 원본 스캔과 **동일한 수치**를 냄(검증: 양쪽 모두 클릭 349,540건 / 소진액 307,367.09), 라이브 INSERT 테스트로 MV가 새 이벤트를 자동 롤업함을 확인.

### 🔑 기억할 함정들

| | 노트 |
|---|---|
| **Scaled-integer 금액** | float 오차를 피하려 통화를 `Int64` 마이크로 단위로 저장. 절대 금액 KPI에만 `/SCALE`; 비율 KPI는 상쇄됨. |
| **하드코딩 대신 파라미터화** | `SCALE`·수수료율·토크나이저 선택 → 파라미터 테이블에서 스칼라 서브쿼리로 읽기. 계약/모델 변경 시 쿼리 SQL 불변. |
| **MATERIALIZED 컬럼은 INSERT하지 않음** | 명시적 `INSERT` 컬럼 리스트에서 제외(계산됨). `ADD COLUMN … MATERIALIZED`는 `MATERIALIZE COLUMN` 실행 전까지 기존 파트를 백필하지 않음. |
| **`*State` ↔ `*Merge` 페어링** | `uniqState`로 쓴 `AggregateFunction(uniq, …)` 컬럼은 `uniqMerge`로 읽음. `*MergeIf` 콤비네이터는 merge 중 필터링. |
| **근사 vs 정확 distinct** | `uniq`는 HyperLogLog(~1% 오차, 작은 메모리); 과금에만 `uniqExact`. |
| **`system.numbers` 아닌 `numbers(N)`** | `numbers(N)`은 종료, `system.numbers`는 무한. |

### 🔍 추가 자료

- [ClickHouse aggregate functions](https://clickhouse.com/docs/sql-reference/aggregate-functions)
- [Combinators (`-If`, `-State`, `-Merge`)](https://clickhouse.com/docs/sql-reference/aggregate-functions/combinators)
- [JSON functions](https://clickhouse.com/docs/sql-reference/functions/json-functions)
- [Dictionaries](https://clickhouse.com/docs/sql-reference/dictionaries)
- [Materialized Views](https://clickhouse.com/docs/materialized-view)

### 📝 검증

빈 상태에서 **ClickHouse 26.6.1.778**(`clickhouse local`)에 대해 모든 스크립트가 end-to-end 검증됨:

| Script | 출력 라인 | 오류 |
|---|---|---|
| `01-schema.sql` | 5 | 0 |
| `02-load.sql` | 10 | 0 |
| `03-cube-basics.sql` | 37 | 0 |
| `04-approx-distinct.sql` | 31 | 0 |
| `05-json-enrichment.sql` | 29 | 0 |
| `06-model-ranking.sql` | 16 | 0 |
| `07-materialized-views.sql` | 15 | 0 |

### 📝 라이선스

MIT License

### 👤 작성자

Ken Lee (ClickHouse Solution Architect) — ken.lee@clickhouse.com
작성일: 2026-06-16

---

**Happy Cubing! 📊**

질문이나 이슈는 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
