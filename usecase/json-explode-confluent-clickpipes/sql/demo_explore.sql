-- =============================================================================
--  데모용 탐색 쿼리 모음 (SQL 콘솔에 붙여넣어 사용)
--  ${...} 는 config.py 가 .env 값으로 치환. 콘솔에서 직접 쓸 땐 실제 이름으로.
--  구성: A 현황  ·  B 변환 before/after  ·  C explode  ·  D 실시간분석  ·  E 품질검증  ·  F 운영
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- A. 파이프라인 현황 (한눈에)
-- ─────────────────────────────────────────────────────────────────────────

-- A1) 세 단계 행 수를 한 줄로
SELECT
    (SELECT count() FROM ${DATABASE}.${TBL_RAW})     AS raw_rows,
    (SELECT count() FROM ${DATABASE}.${TBL_STAGING}) AS staging_rows,
    (SELECT count() FROM ${DATABASE}.${TBL_FACT})    AS fact_lines;

-- A2) 데이터베이스 오브젝트 현황 (엔진 · 행수 · 압축크기)
SELECT
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = '${DATABASE}'
ORDER BY name;

-- A3) 실시간 유입 속도 — 최근 60초간 raw 도착 건수 (초당)
SELECT
    count()                              AS rows_last_60s,
    round(count() / 60, 1)               AS approx_per_sec
FROM ${DATABASE}.${TBL_RAW}
WHERE _ingested_at >= now() - INTERVAL 60 SECOND;

-- A4) MV 파이프라인 최신성 — 각 단계 마지막 도착 시각
SELECT stage, last_seen FROM
(
    SELECT 'raw'     AS stage, toDateTime(max(_ingested_at))         AS last_seen FROM ${DATABASE}.${TBL_RAW}
    UNION ALL
    SELECT 'staging' AS stage, toDateTime(max(_timestamp))          AS last_seen FROM ${DATABASE}.${TBL_STAGING}
    UNION ALL
    SELECT 'fact'    AS stage, toDateTime(max(order_timestamp_local)) AS last_seen FROM ${DATABASE}.${TBL_FACT}
)
ORDER BY stage;


-- ─────────────────────────────────────────────────────────────────────────
-- B. 변환 before / after (transform MV 의 효과)
-- ─────────────────────────────────────────────────────────────────────────

-- B1) RAW 원본 그대로 — 지저분한 상태 (placeholder id, 콤마 가격, 문자열 배열)
SELECT order_id, order_status, created_at, customer_id, order_lines
FROM ${DATABASE}.${TBL_RAW}
ORDER BY _ingested_at DESC
LIMIT 10;

-- B2) STAGING 변환 후 — 타임존 변환 · NULL 정리 · tracking_id 채움
SELECT order_id, order_status, order_timestamp_local, customer_id, tracking_id,
       JSONLength(order_lines) AS n_lines
FROM ${DATABASE}.${TBL_STAGING}
ORDER BY _timestamp DESC
LIMIT 10;

-- B3) 같은 주문 나란히 비교 — raw.customer_id(placeholder) → staging.customer_id(NULL) / tracking_id(대체)
SELECT
    r.order_id                        AS order_id,
    r.customer_id                     AS raw_customer_id,
    s.customer_id                     AS clean_customer_id,   -- placeholder → NULL
    s.tracking_id                     AS tracking_id,         -- NULL 이면 session_id 로 대체됨
    r.created_at                      AS raw_created_at_utc,
    s.order_timestamp_local           AS local_time           -- Asia/Seoul 변환
FROM ${DATABASE}.${TBL_RAW} AS r
INNER JOIN ${DATABASE}.${TBL_STAGING} AS s USING (order_id)
ORDER BY s._timestamp DESC
LIMIT 10;

-- B4) NULL 치환 효과 — placeholder 가 실제로 몇 건이나 NULL 로 정리됐나
SELECT
    countIf(customer_id IS NULL)  AS null_customers,
    countIf(customer_id IS NOT NULL) AS real_customers,
    count()                        AS total
FROM ${DATABASE}.${TBL_STAGING};


-- ─────────────────────────────────────────────────────────────────────────
-- C. explode (order_lines_mv 의 효과: 1 주문 → N 라인)
-- ─────────────────────────────────────────────────────────────────────────

-- C1) 라인이 여러 개인 주문 하나를 골라 → fact 에서 N 행으로 펼쳐진 모습
WITH (
    SELECT order_id FROM ${DATABASE}.${TBL_STAGING}
    WHERE JSONLength(order_lines) >= 3
      AND order_status IN (${VALID_STATUSES_SQL})
    LIMIT 1
) AS pick
SELECT order_id, product_sku, product_name, product_category,
       unit_price, quantity, line_total
FROM ${DATABASE}.${TBL_FACT}
WHERE order_id = pick
ORDER BY product_sku;

-- C2) fact 최신 라인 — 평탄화 · 콤마 가격 파싱 · line_total 계산 결과
SELECT order_id, product_sku, product_category, unit_price, quantity, line_total
FROM ${DATABASE}.${TBL_FACT}
WHERE product_sku != ''
ORDER BY order_timestamp_local DESC
LIMIT 15;

-- C3) 주문당 라인 수 분포 (fan-out 시각화)
SELECT n_lines, count() AS orders
FROM (
    SELECT order_id, count() AS n_lines
    FROM ${DATABASE}.${TBL_FACT}
    WHERE product_sku != ''
    GROUP BY order_id
)
GROUP BY n_lines
ORDER BY n_lines;


-- ─────────────────────────────────────────────────────────────────────────
-- D. 실시간 분석 (fact 기반 — 반복 실행하며 숫자 증가 시연)
-- ─────────────────────────────────────────────────────────────────────────

-- D1) 카테고리별 매출 · 주문 · 라인
SELECT product_category,
       count()             AS line_items,
       sum(line_total)     AS revenue,
       uniqExact(order_id) AS orders
FROM ${DATABASE}.${TBL_FACT}
WHERE order_date = today()
GROUP BY product_category
ORDER BY revenue DESC;

-- D2) 고객 등급(tier)별 객단가
SELECT customer_tier,
       uniqExact(order_id)                       AS orders,
       sum(line_total)                           AS revenue,
       round(sum(line_total) / uniqExact(order_id), 0) AS avg_order_value
FROM ${DATABASE}.${TBL_FACT}
GROUP BY customer_tier
ORDER BY revenue DESC;

-- D3) 분당 주문 추이 (최근 흐름)
SELECT toStartOfMinute(order_timestamp_local) AS minute,
       uniqExact(order_id)                    AS orders,
       sum(line_total)                        AS revenue
FROM ${DATABASE}.${TBL_FACT}
GROUP BY minute
ORDER BY minute DESC
LIMIT 10;

-- D4) 베스트셀러 상품 TOP 5
SELECT product_name,
       sum(quantity)   AS units,
       sum(line_total) AS revenue
FROM ${DATABASE}.${TBL_FACT}
GROUP BY product_name
ORDER BY units DESC
LIMIT 5;


-- ─────────────────────────────────────────────────────────────────────────
-- E. 데이터 품질 / 엣지케이스 검증
-- ─────────────────────────────────────────────────────────────────────────

-- E1) explode_outer — 빈 배열 주문도 row 유지 (product_sku 가 빈 문자열)
SELECT order_status,
       countIf(product_sku = '') AS empty_line_rows,
       count()                   AS total_rows
FROM ${DATABASE}.${TBL_FACT}
GROUP BY order_status
ORDER BY order_status;

-- E2) 상태 필터 — cancelled/returned 는 fact 에 없어야 함 (0 이 정상)
SELECT count() AS cancelled_leaked_into_fact
FROM ${DATABASE}.${TBL_FACT}
WHERE order_id IN (
    SELECT order_id FROM ${DATABASE}.${TBL_STAGING}
    WHERE order_status IN ('cancelled', 'returned')
);

-- E3) 콤마 가격 파싱 — 실패(NULL)가 있는지 (0 이면 전부 파싱 성공)
SELECT countIf(unit_price IS NULL AND product_sku != '') AS price_parse_failures,
       count()                                           AS priced_rows
FROM ${DATABASE}.${TBL_FACT};

-- E4) 정합성 요약 — staging 유효 주문 수 == fact 고유 주문 수
SELECT
    (SELECT uniqExact(order_id) FROM ${DATABASE}.${TBL_STAGING}
     WHERE order_status IN (${VALID_STATUSES_SQL})) AS staging_valid_orders,
    (SELECT uniqExact(order_id) FROM ${DATABASE}.${TBL_FACT}) AS fact_orders;


-- ─────────────────────────────────────────────────────────────────────────
-- F. 운영 / 내부 관찰 (심화 시연)
-- ─────────────────────────────────────────────────────────────────────────

-- F1) 파트 증가 관찰 — 실시간 삽입이 파트를 만드는 모습
SELECT table, count() AS parts, sum(rows) AS rows, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE database = '${DATABASE}' AND active
GROUP BY table
ORDER BY table;

-- F2) MV 정의 확인 — "스케줄러 없이" 자동 실행되는 변환/explode 로직
SHOW CREATE TABLE ${DATABASE}.${MV_TRANSFORM};
SHOW CREATE TABLE ${DATABASE}.${MV_EXPLODE};

-- F3) ClickPipes 에러 테이블 — 파싱 실패 메시지가 있으면 여기로 (비어야 정상)
SELECT count() AS clickpipes_errors
FROM ${DATABASE}.${TBL_RAW}_clickpipes_error;
