-- 데모 쿼리 모음 (instruction §4). ${...} 는 config.py 가 치환.
-- SQL 콘솔에 붙여넣거나 `python scripts/03_verify.py` 로 실행.
-- 쿼리 구분자: 각 블록 앞의 `-- @@` 마커 (verify.py 가 파싱).

-- @@ ① staging 도착 확인: 변환 완료 상태 (타임존/NULL 정리 끝)
SELECT order_id, order_status, order_timestamp_local, customer_id, tracking_id,
       JSONLength(order_lines) AS n_lines
FROM ${DATABASE}.${TBL_STAGING}
ORDER BY _timestamp DESC
LIMIT 10;

-- @@ ② fact 평탄화 확인: 주문 1건 = 라인 N행
SELECT order_id, product_sku, product_name, product_category,
       unit_price, quantity, line_total
FROM ${DATABASE}.${TBL_FACT}
ORDER BY order_timestamp_local DESC
LIMIT 15;

-- @@ ③ 실시간 집계 (반복 실행하며 숫자 증가 시연)
SELECT product_category,
       count()             AS line_items,
       sum(line_total)     AS revenue,
       uniqExact(order_id) AS orders
FROM ${DATABASE}.${TBL_FACT}
WHERE order_date = today()
GROUP BY product_category
ORDER BY revenue DESC;

-- @@ ④a explode_outer 검증: 빈 배열 주문은 row 유지 (product_sku 가 빈 문자열)
SELECT order_status, countIf(product_sku = '') AS empty_line_rows, count() AS rows
FROM ${DATABASE}.${TBL_FACT}
GROUP BY order_status;

-- @@ ④b cancelled/returned 주문은 fact 에 없어야 함
SELECT 'cancelled orders in fact' AS check, count() AS should_be_zero
FROM ${DATABASE}.${TBL_FACT}
WHERE order_id IN (
    SELECT order_id FROM ${DATABASE}.${TBL_STAGING} WHERE order_status = 'cancelled'
);

-- @@ ⑤ 정합성 요약: staging 유효 주문 수 vs fact 고유 주문 수
SELECT
    (SELECT uniqExact(order_id) FROM ${DATABASE}.${TBL_STAGING}
     WHERE order_status IN (${VALID_STATUSES_SQL})) AS staging_valid_orders,
    (SELECT uniqExact(order_id) FROM ${DATABASE}.${TBL_FACT}) AS fact_orders;
