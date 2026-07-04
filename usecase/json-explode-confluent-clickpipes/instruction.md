# 라이브 데모 가이드: 주문 이벤트 실시간 평탄화 (Transform & Explode)

웨비나 "ClickPipes와 Materialized View로 구현하는 실시간 데이터 변환과 평탄화 기반 분석"의
라이브 데모 실행 가이드입니다. 데모 소요 시간은 **약 6–7분**을 목표로 합니다.

두 가지 실행 경로를 준비했습니다.

| 경로 | 구성 | 용도 |
|------|------|------|
| **Path A (본 데모)** | Kafka → ClickPipes → Staging → MV → Fact | 실제 웨비나 시연 — ClickPipes UI까지 보여줌 |
| **Path B (백업)** | Python → HTTP INSERT → Staging → MV → Fact | Kafka/네트워크 장애 시 폴백 — MV 평탄화는 동일하게 시연 가능 |

> 데모 전날 Path A를 끝까지 리허설하고, Path B 스크립트를 터미널에 미리 띄워두세요.
> ClickPipes는 한 번 만들어두면 되므로, 당일에는 생성 과정을 화면 녹화로 대체해도 됩니다.

---

## 0. 사전 준비 (데모 전날)

### 0.1 ClickHouse Cloud

- 서비스 리전: 데이터 소스(Kafka)와 같은 리전 권장
- SQL 콘솔 접속 확인, 데모용 `analytics` 데이터베이스 생성

```sql
CREATE DATABASE IF NOT EXISTS analytics;
```

### 0.2 Kafka (Path A)

Confluent Cloud 무료 클러스터 또는 MSK 사용. 토픽 생성:

```bash
# Confluent CLI 예시
confluent kafka topic create order-events --partitions 3
```

접속 정보 메모: bootstrap server, API key/secret (ClickPipes 설정에 필요)

### 0.3 로컬 환경

```bash
pip install kafka-python clickhouse-connect faker
```

---

## 1. 테이블 · MV 생성 (SQL 콘솔에서 순서대로 실행)

### 1.1 Staging 테이블 — ClickPipes 적재 대상

```sql
CREATE TABLE analytics.orders_staging
(
    order_id               String,
    order_status           LowCardinality(String),
    order_timestamp        DateTime64(3),
    order_timestamp_local  DateTime64(3),
    order_date             Date,
    year_month             String,
    customer_id            Nullable(String),
    customer_tier          LowCardinality(Nullable(String)),
    session_id             Nullable(String),
    tracking_id            String,
    order_lines            String,              -- JSON 배열 문자열 (MV가 전개)
    _timestamp             DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, order_status, tracking_id)
TTL order_date + INTERVAL 7 DAY;
```

### 1.2 Fact 테이블 — 라인 단위 분석 대상

```sql
CREATE TABLE analytics.order_lines_fact
(
    order_id               String,
    order_status           LowCardinality(String),
    order_timestamp_local  DateTime64(3),
    order_date             Date,
    year_month             String,
    customer_id            Nullable(String),
    customer_tier          LowCardinality(Nullable(String)),
    tracking_id            String,
    product_sku            String,
    product_name           String,
    product_category       LowCardinality(String),
    unit_price             Nullable(Decimal64(2)),
    quantity               Nullable(Int32),
    line_total             Nullable(Decimal64(2))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, product_category, tracking_id);
```

### 1.3 Materialized View — Explode 담당

```sql
CREATE MATERIALIZED VIEW analytics.order_lines_mv
TO analytics.order_lines_fact
AS
WITH ['completed', 'processing', 'shipped', 'delivered'] AS valid_statuses
SELECT
    order_id,
    order_status,
    order_timestamp_local,
    order_date,
    year_month,
    customer_id,
    customer_tier,
    tracking_id,
    JSONExtractString(line, 'sku')       AS product_sku,
    JSONExtractString(line, 'name')      AS product_name,
    JSONExtractString(line, 'category')  AS product_category,
    toDecimal64OrNull(replaceAll(JSONExtractString(line, 'unit_price'), ',', ''), 2) AS unit_price,
    toInt32OrNull(JSONExtractString(line, 'qty')) AS quantity,
    toDecimal64OrNull(replaceAll(JSONExtractString(line, 'unit_price'), ',', ''), 2)
        * toInt32OrNull(JSONExtractString(line, 'qty')) AS line_total
FROM analytics.orders_staging
-- explode_outer: 빈 배열이면 '{}' 한 건으로 row 유지
ARRAY JOIN if(JSONLength(order_lines) > 0,
              JSONExtractArrayRaw(order_lines),
              ['{}']) AS line
WHERE order_status IN valid_statuses;
```

---

## 2. ClickPipes 설정 (Path A)

ClickHouse Cloud 콘솔 → **Data sources → ClickPipes → Kafka** 선택 후:

1. **Connection**: bootstrap server + SASL 인증 정보 입력, 토픽 `order-events` 선택
2. **Parse**: JSON 포맷, 샘플 메시지 자동 인식 확인
3. **Transform**: 아래 표대로 target column별 표현식 입력

| Target column | Transform expression |
|---|---|
| `order_timestamp` | `parseDateTime64BestEffort(created_at)` |
| `order_timestamp_local` | `toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul')` |
| `order_date` | `toDate(toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul'))` |
| `year_month` | `formatDateTime(toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul'), '%Y%m')` |
| `customer_id` | `nullIf(nullIf(nullIf(nullIf(customer_id, '(not set)'), 'undefined'), ''), 'null')` |
| `tracking_id` | `coalesce(nullIf(customer_id, ''), session_id)` |
| `order_lines` | `if(order_status IN ('cancelled', 'returned'), '[]', order_lines)` |

4. **Destination**: `analytics.orders_staging` 선택 → 생성

> 시연 포인트: Transform 탭 화면을 잠시 멈추고 "Spark의 withColumn 체인이
> 컬럼별 표현식 하나씩으로 바뀐다"는 것을 강조하세요.

---

## 3. 주문 이벤트 생성기

Spark 예제와 동일한 중첩 JSON 스키마를 발행합니다. 의도적으로 다음을 섞습니다.

- `customer_id`에 placeholder 값 (`(not set)`, `undefined`, 빈 문자열) → NULL 치환 시연
- 가격에 콤마 포함 (`"1,290.00"`) → `replaceAll` 시연
- 10%는 `cancelled`/`returned` → 상태 필터 + 빈 배열 처리 시연
- 5%는 `order_lines`가 빈 배열 → explode_outer 동작 시연

### 3.1 `order_generator.py` (Path A: Kafka 발행)

```python
import json, random, time, uuid
from datetime import datetime, timezone
from kafka import KafkaProducer

BOOTSTRAP = "pkc-xxxxx.ap-northeast-2.aws.confluent.cloud:9092"
API_KEY, API_SECRET = "<KEY>", "<SECRET>"
TOPIC = "order-events"

producer = KafkaProducer(
    bootstrap_servers=BOOTSTRAP,
    security_protocol="SASL_SSL",
    sasl_mechanism="PLAIN",
    sasl_plain_username=API_KEY,
    sasl_plain_password=API_SECRET,
    value_serializer=lambda v: json.dumps(v).encode(),
)

CATALOG = [
    ("SKU-1001", "Wireless Earbuds Pro", "electronics", "129,000"),
    ("SKU-1002", "Mechanical Keyboard",  "electronics", "89,000"),
    ("SKU-2001", "Running Shoes X",      "sports",      "119,000"),
    ("SKU-2002", "Yoga Mat Premium",     "sports",      "35,000"),
    ("SKU-3001", "Cold Brew Set",        "grocery",     "24,500"),
    ("SKU-3002", "Protein Bar 12-pack",  "grocery",     "18,900"),
    ("SKU-4001", "Desk Lamp Minimal",    "home",        "45,000"),
    ("SKU-4002", "Aroma Diffuser",       "home",        "52,000"),
]
STATUSES = ["completed"] * 5 + ["processing"] * 2 + ["shipped", "delivered"] + ["cancelled"]
PLACEHOLDERS = ["(not set)", "undefined", "", "null"]
TIERS = ["bronze", "silver", "gold", "vip"]

def make_order():
    status = random.choice(STATUSES)
    # 5%는 빈 배열 → explode_outer 케이스
    n_lines = 0 if random.random() < 0.05 else random.randint(1, 4)
    lines = []
    for _ in range(n_lines):
        sku, name, cat, price = random.choice(CATALOG)
        lines.append({"sku": sku, "name": name, "category": cat,
                      "unit_price": price, "qty": str(random.randint(1, 3))})
    # 15%는 placeholder customer_id → NULL 치환 케이스
    cust = random.choice(PLACEHOLDERS) if random.random() < 0.15 \
           else f"CUST-{random.randint(1000, 9999)}"
    return {
        "order_id": str(uuid.uuid4()),
        "order_status": status,
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3],
        "customer_id": cust,
        "customer_tier": random.choice(TIERS),
        "session_id": f"sess-{uuid.uuid4().hex[:12]}",
        "order_lines": lines,
    }

if __name__ == "__main__":
    print("producing to", TOPIC, "... Ctrl+C to stop")
    sent = 0
    while True:
        producer.send(TOPIC, make_order())
        sent += 1
        if sent % 50 == 0:
            producer.flush()
            print(f"  sent {sent} orders")
        time.sleep(0.05)   # ~20 orders/sec — 데모용으로 충분
```

### 3.2 `order_generator_direct.py` (Path B: Kafka 없이 직접 INSERT)

ClickPipes 단계 없이 staging에 직접 넣어 **MV 평탄화만** 시연하는 폴백입니다.
ClickPipes가 하던 변환을 INSERT SELECT 안의 동일 표현식으로 수행하므로,
"같은 표현식이 어디서 실행되느냐의 차이일 뿐"이라는 메시지도 살릴 수 있습니다.

```python
import json, random, time
import clickhouse_connect
from order_generator import make_order   # 위 생성 로직 재사용

client = clickhouse_connect.get_client(
    host="<service>.clickhouse.cloud", port=8443,
    username="default", password="<PASSWORD>", secure=True,
)

INSERT_SQL = """
INSERT INTO analytics.orders_staging
    (order_id, order_status, order_timestamp, order_timestamp_local,
     order_date, year_month, customer_id, customer_tier,
     session_id, tracking_id, order_lines)
SELECT
    order_id,
    order_status,
    parseDateTime64BestEffort(created_at),
    toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul'),
    toDate(toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul')),
    formatDateTime(toTimezone(parseDateTime64BestEffort(created_at), 'Asia/Seoul'), '%Y%m'),
    nullIf(nullIf(nullIf(nullIf(customer_id, '(not set)'), 'undefined'), ''), 'null'),
    customer_tier,
    session_id,
    coalesce(nullIf(customer_id, ''), session_id),
    if(order_status IN ('cancelled', 'returned'), '[]', order_lines)
FROM format(JSONEachRow, $${batch}$$)
"""

while True:
    batch = "\n".join(
        json.dumps({**o, "order_lines": json.dumps(o["order_lines"])})
        for o in (make_order() for _ in range(100))
    )
    client.command(INSERT_SQL.replace("{batch}", batch))
    print("inserted 100 orders")
    time.sleep(2)
```

---

## 4. 데모 진행 시나리오 (run of show, 약 6–7분)

| 시간 | 화면 | 행동 · 멘트 포인트 |
|------|------|--------------------|
| 0:00 | 터미널 | `python order_generator.py` 실행 — "주문 1건에 라인 1–4개가 담긴 중첩 JSON이 초당 20건씩 Kafka로 들어갑니다" |
| 0:45 | ClickPipes UI | 파이프 상태 · 처리량 그래프 확인. Transform 탭을 열어 표현식 강조 |
| 1:30 | SQL 콘솔 | 쿼리 ① staging 도착 확인 — "타임존 변환과 NULL 정리가 이미 끝난 상태로 도착" |
| 2:30 | SQL 콘솔 | 쿼리 ② fact 확인 — "같은 order_id가 라인 수만큼 행으로 전개. MV를 손으로 실행한 적 없음" |
| 3:30 | SQL 콘솔 | 쿼리 ③ 실시간 집계를 5초 간격으로 2–3회 재실행 — 숫자가 커지는 것 시연 |
| 4:30 | SQL 콘솔 | 쿼리 ④ explode_outer 검증 — 빈 배열 주문이 row로 유지, cancelled는 부재 |
| 5:30 | SQL 콘솔 | 쿼리 ⑤ 정합성 요약 — staging 주문 수 vs fact 라인 수 |
| 6:00 | 슬라이드 복귀 | "스케줄러도, 배치 잡도, Spark 클러스터도 없었습니다" 로 마무리 |

### 데모 쿼리 모음 (SQL 콘솔에 미리 붙여넣어 둘 것)

```sql
-- ① staging 도착 확인: 변환 완료 상태
SELECT order_id, order_status, order_timestamp_local, customer_id, tracking_id,
       JSONLength(order_lines) AS n_lines
FROM analytics.orders_staging
ORDER BY _timestamp DESC
LIMIT 10;

-- ② fact 평탄화 확인: 주문 1건 = 라인 N행
SELECT order_id, product_sku, product_name, product_category,
       unit_price, quantity, line_total
FROM analytics.order_lines_fact
ORDER BY order_timestamp_local DESC
LIMIT 15;

-- ③ 실시간 집계 (반복 실행하며 숫자 증가 시연)
SELECT product_category,
       count()                    AS line_items,
       sum(line_total)            AS revenue,
       uniqExact(order_id)        AS orders
FROM analytics.order_lines_fact
WHERE order_date = today()
GROUP BY product_category
ORDER BY revenue DESC;

-- ④ explode_outer 검증: 빈 배열 주문은 row 유지, cancelled/returned는 fact에 없음
SELECT order_status, countIf(product_sku = '') AS empty_line_rows, count() AS rows
FROM analytics.order_lines_fact
GROUP BY order_status;

SELECT 'cancelled orders in fact' AS check, count() AS should_be_zero
FROM analytics.order_lines_fact
WHERE order_id IN (
    SELECT order_id FROM analytics.orders_staging WHERE order_status = 'cancelled'
);

-- ⑤ 정합성 요약: staging 유효 주문 수 vs fact 고유 주문 수
SELECT
    (SELECT uniqExact(order_id) FROM analytics.orders_staging
     WHERE order_status IN ('completed','processing','shipped','delivered')) AS staging_valid_orders,
    (SELECT uniqExact(order_id) FROM analytics.order_lines_fact)             AS fact_orders;
```

---

## 5. 트러블슈팅 (당일 대비)

| 증상 | 원인 · 대응 |
|------|------------|
| staging에 데이터가 안 들어옴 | ClickPipes 상태 · Kafka 인증 확인. 5분 내 복구 안 되면 Path B로 전환 |
| fact가 비어 있음 | MV가 staging보다 **나중에** 생성됐는지 확인 — MV는 생성 이후 INSERT만 처리. 기존 데이터는 `INSERT INTO fact SELECT ... FROM staging ARRAY JOIN ...`으로 백필 |
| 집계 숫자가 안 늘어남 | 생성기 프로세스 생존 확인, `system.parts`로 staging 파트 증가 확인 |
| unit_price가 NULL | 가격 콤마 포맷 확인 — `toDecimal64OrNull`은 실패 시 NULL 반환 (의도된 안전장치라고 설명 가능) |
| 데모 재시작 필요 | `TRUNCATE TABLE analytics.orders_staging; TRUNCATE TABLE analytics.order_lines_fact;` 후 생성기 재실행 |

---

## 6. 웨비나 전체 타임라인 제안 (25분)

| 구간 | 슬라이드 | 시간 |
|------|----------|------|
| 인트로 + 목차 | 1–2 | 1분 |
| 01 Spark Streaming의 현실 | 3–6 | 5분 |
| 02 대안 아키텍처 | 7–11 | 6분 |
| 03 실전 구현 | 12–17 | 6분 |
| 04 벤치마크 · 비용 | 18–21 | 3분 |
| 라이브 데모 | 22 + 화면 전환 | 6–7분 (Q&A 시간에 따라 조절) |
| 결론 + 클로징 | 23–24 | 1분 |