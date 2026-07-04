-- =============================================================================
--  스키마 정의: raw → (transform MV) → staging → (explode MV) → fact
--  ${...} 플레이스홀더는 scripts/config.py 가 .env 값으로 치환합니다.
--
--  설계 노트:
--    ClickPipes REST API 의 fieldMappings 는 컬럼 "이름 매핑"만 지원하고
--    컬럼별 변환 표현식(타임존/NULL 정리/coalesce/if)은 지원하지 않습니다.
--    그래서 ClickPipes 는 원본 JSON 을 ${TBL_RAW} 에 그대로 적재하고,
--    instruction 의 Transform 표현식은 아래 ${MV_TRANSFORM} 가 대신 수행합니다.
--    "같은 표현식이 어디서 실행되느냐의 차이일 뿐" — MV 안에서 실행될 뿐입니다.
-- =============================================================================

-- ①  Raw 랜딩 테이블 — ClickPipes 적재 대상 (existing/unmanaged table)
--     모든 컬럼은 Kafka JSON 필드명 그대로, 변환 없이 String 으로 받습니다.
CREATE TABLE IF NOT EXISTS ${DATABASE}.${TBL_RAW}
(
    order_id       String,
    order_status   String,
    created_at     String,
    customer_id    String,
    customer_tier  String,
    session_id     String,
    order_lines    String,          -- JSON 배열 "문자열" (producer 가 stringify 해서 발행)
    _ingested_at   DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (order_id);

-- ②  Staging 테이블 — 변환 완료 상태 (instruction 1.1 과 동일)
CREATE TABLE IF NOT EXISTS ${DATABASE}.${TBL_STAGING}
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
    order_lines            String,                    -- JSON 배열 문자열 (explode MV 가 전개)
    _timestamp             DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (order_date, order_status, tracking_id)
TTL order_date + INTERVAL ${STAGING_TTL_DAYS} DAY;

-- ③  Fact 테이블 — 라인 단위 분석 대상 (instruction 1.2 와 동일)
CREATE TABLE IF NOT EXISTS ${DATABASE}.${TBL_FACT}
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

-- ④  Transform MV — raw → staging (ClickPipes Transform 탭 표현식을 대체)
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DATABASE}.${MV_TRANSFORM}
TO ${DATABASE}.${TBL_STAGING}
AS
SELECT
    order_id,
    order_status,
    parseDateTime64BestEffort(created_at)                                        AS order_timestamp,
    toTimezone(parseDateTime64BestEffort(created_at), '${LOCAL_TZ}')             AS order_timestamp_local,
    toDate(toTimezone(parseDateTime64BestEffort(created_at), '${LOCAL_TZ}'))     AS order_date,
    formatDateTime(toTimezone(parseDateTime64BestEffort(created_at), '${LOCAL_TZ}'), '%Y%m') AS year_month,
    nullIf(nullIf(nullIf(nullIf(customer_id, '(not set)'), 'undefined'), ''), 'null')        AS customer_id,
    customer_tier,
    session_id,
    coalesce(nullIf(customer_id, ''), session_id)                                AS tracking_id,
    if(order_status IN ('cancelled', 'returned'), '[]', order_lines)             AS order_lines
FROM ${DATABASE}.${TBL_RAW};

-- ⑤  Explode MV — staging → fact (instruction 1.3 과 동일)
CREATE MATERIALIZED VIEW IF NOT EXISTS ${DATABASE}.${MV_EXPLODE}
TO ${DATABASE}.${TBL_FACT}
AS
WITH [${VALID_STATUSES_SQL}] AS valid_statuses
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
FROM ${DATABASE}.${TBL_STAGING}
-- explode_outer: 빈 배열이면 '{}' 한 건으로 row 유지
ARRAY JOIN if(JSONLength(order_lines) > 0,
              JSONExtractArrayRaw(order_lines),
              ['{}']) AS line
WHERE order_status IN valid_statuses;
