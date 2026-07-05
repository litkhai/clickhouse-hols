# 실시간 주문 이벤트 평탄화 데모 — 자동화판

**Confluent Cloud → ClickPipes → ClickHouse Cloud** 경로를, 로컬에서 명령 몇 줄로
띄웠다 내리는 자동화 스크립트입니다. 웨비나
*"ClickPipes와 Materialized View로 구현하는 실시간 데이터 변환과 평탄화 기반 분석"* 의
라이브 데모(약 6–7분)를 그대로 재현합니다.

원본 시나리오·멘트·타임라인은 [instruction.md](instruction.md) 를 보세요.
이 문서는 **자동 실행 방법**만 다룹니다.

> 저자: Ken Lee (ClickHouse SA) · 라이선스: MIT

---

## 아키텍처

```
 로컬 producer ──JSON──▶ Confluent Cloud (order-events)
                               │
                               ▼  ClickPipes (API로 자동 생성)
                     analytics.orders_raw        ← 원본 JSON 그대로 적재
                               │  orders_transform_mv  (타임존/NULL 정리/coalesce/if)
                               ▼
                     analytics.orders_staging    ← 변환 완료 (데모 쿼리 ①)
                               │  order_lines_mv       (JSON 배열 ARRAY JOIN = explode)
                               ▼
                     analytics.order_lines_fact  ← 라인 단위 평탄화 (데모 쿼리 ②~⑤)
```

### 왜 MV가 2개인가 (원본과의 차이)

원본 instruction 은 **변환을 ClickPipes Transform 탭**에서, **explode 를 MV 하나**에서
수행합니다. 그런데 ClickPipes **REST API(`fieldMappings`)는 컬럼 이름 매핑만 지원하고
컬럼별 변환 표현식은 지원하지 않습니다.** (`sourceField → destinationField` 뿐)

그래서 API 완전 자동화를 위해 **변환 표현식을 `orders_transform_mv` 로 옮겼습니다.**
ClickPipes 는 원본 JSON 을 `orders_raw` 에 그대로 넣고, 변환·explode 는 모두
ClickHouse MV 가 담당합니다. 표현식 자체는 instruction §2 표와 **완전히 동일**하며,
*"같은 표현식이 어디서 실행되느냐의 차이일 뿐"* 이라는 메시지와 오히려 잘 맞습니다.

---

## 준비물

| 항목 | 필요한 값 (→ `.env`) |
|------|----------------------|
| ClickHouse Cloud (SQL) | `CH_HOST`, `CH_PORT`, `CH_USER`, `CH_PASSWORD` |
| ClickHouse Cloud (OpenAPI, ClickPipes 자동화) | `CH_API_KEY_ID`, `CH_API_KEY_SECRET`, `CH_ORG_ID`, `CH_SERVICE_ID` |
| Confluent Cloud Kafka | `KAFKA_BOOTSTRAP`, `KAFKA_API_KEY`, `KAFKA_API_SECRET`, `KAFKA_TOPIC` |
| 스키마/이름/동작 | DB·테이블·MV 이름, 타임존, 유효 상태, producer 튜닝 (모두 `.env`) |

- **Kafka 토픽은 미리 존재**해야 합니다(이 데모는 토픽을 자동 생성하지 않음):
  `confluent kafka topic create order-events --partitions 3`
- ClickHouse API Key: 콘솔 → 조직 설정 → **API Keys**
- Org ID / Service ID: 콘솔 URL 또는 서비스 상세 페이지에서 확인

> `.env` 는 `.gitignore` 로 커밋되지 않습니다. **API 키/시크릿을 절대 커밋하지 마세요.**

---

## 설정

```bash
cd usecase/json-explode-confluent-clickpipes

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
$EDITOR .env          # 위 표의 값들을 채웁니다
```

---

## 사전 준비 (1회, 전날)

```bash
# ① ClickHouse 스키마 생성 (DB + raw/staging/fact + MV 2개). 멱등적.
python scripts/00_setup_clickhouse.py

# ② ClickPipes 자동 생성 (Confluent → orders_raw). 같은 이름 있으면 재사용.
#    주의: 토픽에 메시지가 최소 1건 있어야 스키마 샘플링이 통과합니다.
#    → offset=from_beginning (기본) 이면 씨드 몇 건만 넣고 만들면 됩니다.
python scripts/01_create_clickpipe.py
```

## 데모 당일 (원클릭)

```bash
# ▶ 터미널 1 — 점검(연결·스키마·ClickPipe 가동) 후 메시지 계속 발행 (기본 1초에 1건)
python scripts/start_demo.py
#    점검만:            python scripts/start_demo.py --check
#    속도 임시 변경:     python scripts/start_demo.py --rate 5

# 터미널 2 — 실시간 집계가 커지는 것 시연
python scripts/03_verify.py --watch     # ③ 집계 3초마다 반복
python scripts/03_verify.py             # ①~⑤ 한 번씩

# 반복 데모 사이 초기화 (테이블만 0으로, ClickPipe·스키마 유지)
python scripts/clean.py
```

> **발행 속도**는 `.env` 의 `PRODUCE_RATE` 로 정합니다. 기본 **1/s** — 시연 관점에서
> 숫자가 또렷하게 한 건씩 올라가 직관적입니다. 부하 시연은 `PRODUCE_RATE=20` 등으로.

개별 스크립트로 돌리고 싶으면 `python scripts/02_produce.py` (발행만) 도 그대로 씁니다.

### 데모 흐름과의 매핑

| instruction 단계 | 이 스크립트 |
|---|---|
| `python order_generator.py` | `scripts/02_produce.py` |
| ClickPipes UI 생성 | `scripts/01_create_clickpipe.py` (API 자동) |
| SQL 콘솔 쿼리 ①~⑤ | `scripts/03_verify.py` |
| 테이블/MV 생성 | `scripts/00_setup_clickhouse.py` + `sql/schema.sql` |

라이브 시연에서는 SQL 콘솔에 [sql/demo_queries.sql](sql/demo_queries.sql) 을
미리 붙여넣어 두고, `03_verify.py` 는 백업/사전확인용으로 쓰면 됩니다.

---

## 정리 / 재시작

```bash
# 데모 재시작: ClickPipe 유지, 테이블만 비움 → producer 다시 실행
python scripts/99_teardown.py

# 완전 삭제: ClickPipe + 테이블/MV DROP
python scripts/99_teardown.py --drop

# DB 까지 삭제
python scripts/99_teardown.py --drop-db
```

---

## 파일 구성

```
.
├── instruction.md              # 원본 웨비나 데모 가이드 (시나리오·멘트)
├── .env.example                # 설정 템플릿 (복사해서 .env 로)
├── .gitignore                  # .env / 상태파일 / venv 제외
├── requirements.txt
├── sql/
│   ├── schema.sql              # raw/staging/fact + MV 2개 (${...} 템플릿)
│   └── demo_queries.sql        # 데모 쿼리 ①~⑤
└── scripts/
    ├── config.py               # .env 로더 + SQL 렌더러 + CH 클라이언트
    ├── clickpipe_api.py        # ClickPipes OpenAPI 헬퍼 (생성/상태/삭제)
    ├── order_generator.py      # 주문 이벤트 생성 로직 (공용)
    ├── producer.py             # Kafka 발행 코어 (공용)
    ├── 00_setup_clickhouse.py  # 스키마 생성
    ├── 01_create_clickpipe.py  # ClickPipes 생성
    ├── 02_produce.py           # Kafka 발행 (발행만)
    ├── 03_verify.py            # 데모 쿼리 실행
    ├── start_demo.py           # ▶ 원클릭: 점검 + ClickPipe 가동 + 발행
    ├── clean.py                # 테이블 0으로 초기화 (반복 데모용)
    └── 99_teardown.py          # 정리 (ClickPipe 삭제 + DROP)
```

---

## 트러블슈팅

| 증상 | 대응 |
|------|------|
| `01_create_clickpipe.py` 401 | `CH_API_KEY_ID/SECRET`, `CH_ORG_ID`, `CH_SERVICE_ID` 재확인 |
| staging/fact 가 비어 있음 | ClickPipe `state` 가 `Running` 인지 콘솔 확인. producer 가 돌고 있는지 확인 |
| `unit_price` 가 NULL | 가격 콤마 포맷 확인 — `toDecimal64OrNull` 은 실패 시 NULL (의도된 안전장치) |
| ClickPipe 생성은 됐는데 데이터 없음 | `KAFKA_SASL_MECHANISM` 이 클러스터 설정과 일치하는지, 토픽 이름이 맞는지 확인 |
| 데모 다시 처음부터 | `python scripts/99_teardown.py` 후 `02_produce.py` 재실행 |

> 스키마 파이프라인(raw→staging→fact, explode_outer, cancelled 필터, 콤마 가격 파싱)은
> ClickHouse 26.7 에서 검증되었습니다.
