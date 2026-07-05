# Real-time JSON Explode Demo — Confluent → ClickPipes → ClickHouse / 실시간 JSON 평탄화 데모

[English](#english) | [한국어](#한국어)

Author: Ken Lee (ClickHouse SA) · License: MIT

---

## English

A fully-automated, one-command version of the webinar live demo *"Real-time data transformation and flattening-based analytics with ClickPipes and Materialized Views."* You produce nested order-event JSON locally, it flows through **Confluent Cloud → ClickPipes → ClickHouse Cloud**, and two Materialized Views transform and **explode** each order into per-line fact rows — with **no scheduler, no batch job, no Spark cluster**.

Everything (schema, object names, credentials, demo behavior) is configured in a single gitignored `.env`. A bilingual (ko/en) **web dashboard** ships in `webapp/` and runs via Docker.

> The original narrative, run-of-show and talk track live in [instruction.md](instruction.md). This README covers **how to run the automation**.

### Architecture

```
 local producer ──JSON──▶ Confluent Cloud (topic)
                                │
                                ▼  ClickPipes (created via ClickHouse Cloud OpenAPI)
                      analytics.orders_raw          ← raw JSON landed as-is
                                │  orders_transform_mv  (timezone / NULL cleanup / coalesce / if)
                                ▼
                      analytics.orders_staging      ← transformed (demo query ①)
                                │  order_lines_mv       (JSON array ARRAY JOIN = explode)
                                ▼
                      analytics.order_lines_fact    ← per-line flattened (demo queries ②~⑤)
```

### Why two Materialized Views (difference from the original)

The original instruction does the **transform in the ClickPipes UI** and the **explode in one MV**. But the ClickPipes **REST API (`fieldMappings`) only supports column name mapping — not per-column transform expressions** (`sourceField → destinationField` only).

So to make it **fully API-automatable**, the transform expressions moved into `orders_transform_mv`. ClickPipes lands the raw JSON into `orders_raw`, and both the transform and the explode run as ClickHouse MVs. The expressions are **identical to instruction §2** — this actually reinforces the message *"it's just a matter of where the same expressions run."*

### Prerequisites

| Item | Values (→ `.env`) |
|---|---|
| ClickHouse Cloud (SQL) | `CH_HOST`, `CH_PORT`, `CH_USER`, `CH_PASSWORD` |
| ClickHouse Cloud (OpenAPI, for ClickPipes automation) | `CH_API_KEY_ID`, `CH_API_KEY_SECRET`, `CH_ORG_ID`, `CH_SERVICE_ID` |
| Confluent Cloud Kafka | `KAFKA_BOOTSTRAP` (`:9092`), `KAFKA_API_KEY`, `KAFKA_API_SECRET`, `KAFKA_TOPIC` |
| Schema / names / behavior | DB, table & MV names, timezone, valid statuses, producer knobs |

- **The Kafka topic must already exist** (this demo does not auto-create it):
  `confluent kafka topic create order-events --partitions 3`
- **Kafka API key must be a *cluster-scoped* key**, not an org/Cloud API key (SASL/PLAIN on port 9092).
- ClickHouse API key: Console → Organization → API Keys. Org/Service IDs are in the console URLs.

### Setup

```bash
cd usecase/json-explode-confluent-clickpipes
cp .env.example .env      # fill in the values above
```

### One-time provisioning (day before)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scripts/00_setup_clickhouse.py   # DB + raw/staging/fact + 2 MVs (idempotent)
python scripts/01_create_clickpipe.py   # ClickPipe via OpenAPI (topic needs ≥1 message to sample)
```

### Run — Option A: web dashboard (Docker, recommended)

```bash
docker compose up -d --build     # → http://localhost:8080
docker compose logs -f
docker compose down
```

The dashboard (default Korean, switchable to English top-right):

- **Top menu**: `Start` (=resume) / `Stop` (=pause) / `Cleanup`, plus a configurable **interval** (default **3 s per message** for an intuitive, one-at-a-time flow).
- **Left**: the 4-stage pipeline — **1 Client → 2 Kafka (live topic tail) → 3 Staging → 4 Fact** — each table shows 5 rows then scrolls; auto-refreshes. Click a Kafka `raw` cell to see the **full JSON**.
- **Right**: preset queries in **3 categories** (Status Monitoring / Performance / Business) — click to run.

Secrets are **not baked into the image** (`.dockerignore` excludes `.env`); they are injected at runtime via `env_file` in `docker-compose.yml`.

### Run — Option B: CLI scripts

```bash
python scripts/start_demo.py          # preflight (conn + schema + pipe) then produce (default 3 s/msg)
python scripts/start_demo.py --check  # preflight only
python scripts/03_verify.py --watch   # repeat the aggregation query, watch numbers grow
python scripts/clean.py               # truncate tables between runs (keeps pipe + schema)
```

### Preset queries

Also available as SQL files: [sql/demo_explore.sql](sql/demo_explore.sql), [sql/demo_queries.sql](sql/demo_queries.sql).

- **Status Monitoring** — row counts, per-stage freshness, orders by status, transform before/after, NULL-cleanup effect, explode_outer check, cancelled exclusion, reconciliation.
- **Performance** — object overview, parts, compression ratio, per-column storage.
- **Business** — revenue by category, AOV by tier, best sellers, orders/min, lines-per-order, basket breakdown.

### File structure

```
json-explode-confluent-clickpipes/
├── instruction.md              # original webinar run-of-show
├── .env.example                # config template (copy → .env)
├── .gitignore / .dockerignore  # exclude secrets
├── Dockerfile / docker-compose.yml
├── requirements.txt
├── sql/
│   ├── schema.sql              # raw/staging/fact + 2 MVs (${...} templated)
│   ├── demo_queries.sql        # core demo queries ①~⑤
│   └── demo_explore.sql        # extended exploration queries
├── scripts/
│   ├── config.py               # .env loader + SQL renderer + CH client
│   ├── clickpipe_api.py        # ClickPipes OpenAPI helper (create/state/delete)
│   ├── order_generator.py      # order event generator (shared)
│   ├── producer.py             # Kafka producer core (shared)
│   ├── 00_setup_clickhouse.py  # create schema
│   ├── 01_create_clickpipe.py  # create ClickPipe
│   ├── 02_produce.py           # produce only
│   ├── 03_verify.py            # run demo queries
│   ├── start_demo.py           # ▶ one-click: preflight + start pipe + produce
│   ├── clean.py                # truncate tables (repeat demos)
│   └── 99_teardown.py          # delete ClickPipe + DROP objects
└── webapp/
    ├── app.py                  # Flask backend
    ├── demo_state.py           # producer thread + Kafka tail + cleanup
    ├── presets.py              # preset queries (bilingual)
    ├── templates/index.html
    └── static/{app.js,style.css}
```

### Cleanup / teardown

```bash
python scripts/99_teardown.py            # delete ClickPipe + TRUNCATE (safe default)
python scripts/99_teardown.py --drop     # + DROP tables/MVs
python scripts/99_teardown.py --drop-db  # + DROP database
```

### Troubleshooting

| Symptom | Fix |
|---|---|
| Kafka `SaslAuthenticationFailedError` | Use a **cluster-scoped** Kafka API key; bootstrap must be host`:9092` (no `https://`) |
| ClickPipe create `no data received from source` | Topic is empty — seed a few messages first, or use `CLICKPIPE_OFFSET=from_beginning` |
| ClickPipe create `Columns are required...` | Handled: destination `columns` are sent with `fieldMappings` |
| staging/fact empty | Check the ClickPipe is `Running` and the producer is running |
| `unit_price` is NULL | Comma price parse — `toDecimal64OrNull` returns NULL on failure (intentional safety) |

Verified end-to-end on ClickHouse Cloud (v26.4) with Confluent Cloud.

---

## 한국어

웨비나 *"ClickPipes와 Materialized View로 구현하는 실시간 데이터 변환과 평탄화 기반 분석"* 라이브 데모를 **명령 한 줄로 자동화**한 버전입니다. 로컬에서 중첩된 주문 이벤트 JSON을 발행하면 **Confluent Cloud → ClickPipes → ClickHouse Cloud**로 흐르고, 두 개의 Materialized View가 이를 변환하고 주문을 라인 단위로 **explode(평탄화)**합니다 — **스케줄러도, 배치 잡도, Spark 클러스터도 없이.**

모든 것(스키마·오브젝트 이름·크리덴셜·동작)은 gitignore된 단일 `.env`에서 설정합니다. 이중언어(ko/en) **웹 대시보드**가 `webapp/`에 포함되어 Docker로 실행됩니다.

> 원본 시나리오·멘트·타임라인은 [instruction.md](instruction.md) 를 보세요. 이 문서는 **자동 실행 방법**을 다룹니다.

### 아키텍처

```
 로컬 producer ──JSON──▶ Confluent Cloud (topic)
                                │
                                ▼  ClickPipes (ClickHouse Cloud OpenAPI로 자동 생성)
                      analytics.orders_raw          ← 원본 JSON 그대로 적재
                                │  orders_transform_mv  (타임존 / NULL 정리 / coalesce / if)
                                ▼
                      analytics.orders_staging      ← 변환 완료 (데모 쿼리 ①)
                                │  order_lines_mv       (JSON 배열 ARRAY JOIN = explode)
                                ▼
                      analytics.order_lines_fact    ← 라인 단위 평탄화 (데모 쿼리 ②~⑤)
```

### 왜 MV가 2개인가 (원본과의 차이)

원본 instruction은 **변환을 ClickPipes UI**에서, **explode를 MV 하나**로 수행합니다. 그런데 ClickPipes **REST API(`fieldMappings`)는 컬럼 이름 매핑만 지원하고 컬럼별 변환 표현식은 지원하지 않습니다** (`sourceField → destinationField` 뿐).

그래서 **API 완전 자동화**를 위해 변환 표현식을 `orders_transform_mv`로 옮겼습니다. ClickPipes는 원본 JSON을 `orders_raw`에 넣고, 변환·explode는 모두 ClickHouse MV가 담당합니다. 표현식은 **instruction §2와 완전히 동일**하며, 오히려 *"같은 표현식이 어디서 실행되느냐의 차이일 뿐"* 이라는 메시지와 잘 맞습니다.

### 준비물

| 항목 | 값 (→ `.env`) |
|---|---|
| ClickHouse Cloud (SQL) | `CH_HOST`, `CH_PORT`, `CH_USER`, `CH_PASSWORD` |
| ClickHouse Cloud (OpenAPI, ClickPipes 자동화) | `CH_API_KEY_ID`, `CH_API_KEY_SECRET`, `CH_ORG_ID`, `CH_SERVICE_ID` |
| Confluent Cloud Kafka | `KAFKA_BOOTSTRAP` (`:9092`), `KAFKA_API_KEY`, `KAFKA_API_SECRET`, `KAFKA_TOPIC` |
| 스키마 / 이름 / 동작 | DB·테이블·MV 이름, 타임존, 유효 상태, producer 튜닝 |

- **Kafka 토픽은 미리 존재**해야 합니다(자동 생성 안 함):
  `confluent kafka topic create order-events --partitions 3`
- **Kafka API 키는 반드시 *클러스터 스코프* 키**여야 합니다(조직/Cloud 키 아님, 9092 포트 SASL/PLAIN).
- ClickHouse API 키: 콘솔 → 조직 → API Keys. Org/Service ID는 콘솔 URL에서 확인.

### 설정

```bash
cd usecase/json-explode-confluent-clickpipes
cp .env.example .env      # 위 표의 값들을 채웁니다
```

### 사전 준비 (전날, 1회)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scripts/00_setup_clickhouse.py   # DB + raw/staging/fact + MV 2개 (멱등적)
python scripts/01_create_clickpipe.py   # OpenAPI로 ClickPipe 생성 (토픽에 메시지 ≥1건 필요)
```

### 실행 — 방법 A: 웹 대시보드 (Docker, 권장)

```bash
docker compose up -d --build     # → http://localhost:8080
docker compose logs -f
docker compose down
```

대시보드 (기본 한국어, 우상단에서 English 전환 가능):

- **상단 메뉴**: `Start`(=재개) / `Stop`(=일시정지) / `Cleanup`, 그리고 **interval** 설정(기본 **3초에 1건** — 한 건씩 흐르는 게 직관적).
- **좌측**: 4단계 파이프라인 — **1 Client → 2 Kafka(토픽 실시간 tail) → 3 Staging → 4 Fact** — 각 테이블은 5줄까지 보이고 이후 스크롤, 자동 갱신. Kafka `raw` 셀을 클릭하면 **전체 JSON**을 봅니다.
- **우측**: 프리셋 쿼리 **3개 카테고리**(상태 모니터링 / 성능 / 비즈니스) — 클릭하면 실행.

시크릿은 **이미지에 굽히지 않습니다**(`.dockerignore`가 `.env` 제외). `docker-compose.yml`의 `env_file`로 **실행 시에만 주입**됩니다.

### 실행 — 방법 B: CLI 스크립트

```bash
python scripts/start_demo.py          # 점검(연결+스키마+파이프) 후 발행 (기본 3초/건)
python scripts/start_demo.py --check  # 점검만
python scripts/03_verify.py --watch   # 집계 쿼리 반복 실행, 숫자 증가 시연
python scripts/clean.py               # 반복 데모용 테이블 초기화 (파이프·스키마 유지)
```

### 프리셋 쿼리

SQL 파일로도 제공: [sql/demo_explore.sql](sql/demo_explore.sql), [sql/demo_queries.sql](sql/demo_queries.sql).

- **상태 모니터링** — 행 수, 각 단계 최신성, 상태별 주문 분포, 변환 before/after, NULL 치환 효과, explode_outer 검증, cancelled 누락 검증, 정합성.
- **성능 관련 지표** — 오브젝트 현황, 파트, 압축률, 컬럼별 저장 크기.
- **비즈니스 집계** — 카테고리별 매출, 등급별 객단가, 베스트셀러, 분당 주문, 주문당 라인 수, 장바구니 구성.

### 파일 구성

```
json-explode-confluent-clickpipes/
├── instruction.md              # 원본 웨비나 데모 가이드
├── .env.example                # 설정 템플릿 (복사 → .env)
├── .gitignore / .dockerignore  # 시크릿 제외
├── Dockerfile / docker-compose.yml
├── requirements.txt
├── sql/
│   ├── schema.sql              # raw/staging/fact + MV 2개 (${...} 템플릿)
│   ├── demo_queries.sql        # 핵심 데모 쿼리 ①~⑤
│   └── demo_explore.sql        # 확장 탐색 쿼리
├── scripts/
│   ├── config.py               # .env 로더 + SQL 렌더러 + CH 클라이언트
│   ├── clickpipe_api.py        # ClickPipes OpenAPI 헬퍼 (생성/상태/삭제)
│   ├── order_generator.py      # 주문 이벤트 생성 로직 (공용)
│   ├── producer.py             # Kafka 발행 코어 (공용)
│   ├── 00_setup_clickhouse.py  # 스키마 생성
│   ├── 01_create_clickpipe.py  # ClickPipe 생성
│   ├── 02_produce.py           # 발행 전용
│   ├── 03_verify.py            # 데모 쿼리 실행
│   ├── start_demo.py           # ▶ 원클릭: 점검 + 파이프 가동 + 발행
│   ├── clean.py                # 테이블 초기화 (반복 데모)
│   └── 99_teardown.py          # ClickPipe 삭제 + 오브젝트 DROP
└── webapp/
    ├── app.py                  # Flask 백엔드
    ├── demo_state.py           # producer 스레드 + Kafka tail + 초기화
    ├── presets.py              # 프리셋 쿼리 (이중언어)
    ├── templates/index.html
    └── static/{app.js,style.css}
```

### 정리 / 삭제

```bash
python scripts/99_teardown.py            # ClickPipe 삭제 + TRUNCATE (안전 기본값)
python scripts/99_teardown.py --drop     # + 테이블/MV DROP
python scripts/99_teardown.py --drop-db  # + 데이터베이스 DROP
```

### 트러블슈팅

| 증상 | 대응 |
|---|---|
| Kafka `SaslAuthenticationFailedError` | **클러스터 스코프** Kafka API 키 사용, bootstrap은 host`:9092` (`https://` 없이) |
| ClickPipe 생성 `no data received from source` | 토픽이 비어 있음 — 씨드 몇 건 넣거나 `CLICKPIPE_OFFSET=from_beginning` |
| ClickPipe 생성 `Columns are required...` | 처리됨: `fieldMappings`와 함께 destination `columns` 전송 |
| staging/fact 비어 있음 | ClickPipe가 `Running`인지, producer가 돌고 있는지 확인 |
| `unit_price`가 NULL | 콤마 가격 파싱 — `toDecimal64OrNull`은 실패 시 NULL (의도된 안전장치) |

ClickHouse Cloud(v26.4) + Confluent Cloud에서 전 구간 검증 완료.
