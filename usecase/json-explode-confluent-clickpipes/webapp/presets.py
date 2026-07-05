"""우측 하단 프리셋 쿼리 — 클릭하면 실행되는 데모 쿼리 목록.

sql/demo_explore.sql 의 핵심을 UI 버튼용으로 추린 것.
"""
from config import CFG

D = CFG.database
RAW, STG, FCT = CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact
VALID = CFG.valid_statuses_sql()

PRESETS = [
    {
        "id": "counts",
        "label": "① 파이프라인 행 수",
        "sql": f"""SELECT (SELECT count() FROM {D}.{RAW}) AS raw_rows,
       (SELECT count() FROM {D}.{STG}) AS staging_rows,
       (SELECT count() FROM {D}.{FCT}) AS fact_lines""",
    },
    {
        "id": "objects",
        "label": "② 오브젝트 현황",
        "sql": f"""SELECT name, engine, total_rows, formatReadableSize(total_bytes) AS size
FROM system.tables WHERE database='{D}' ORDER BY name""",
    },
    {
        "id": "beforeafter",
        "label": "③ 변환 before/after",
        "sql": f"""SELECT r.customer_id AS raw_customer_id, s.customer_id AS clean_customer_id,
       s.tracking_id, r.created_at AS raw_utc, s.order_timestamp_local AS local_kst
FROM {D}.{RAW} r INNER JOIN {D}.{STG} s USING (order_id)
ORDER BY s._timestamp DESC LIMIT 12""",
    },
    {
        "id": "nullfix",
        "label": "④ NULL 치환 효과",
        "sql": f"""SELECT countIf(customer_id IS NULL) AS null_customers,
       countIf(customer_id IS NOT NULL) AS real_customers, count() AS total
FROM {D}.{STG}""",
    },
    {
        "id": "explode",
        "label": "⑤ explode (1주문→N라인)",
        "sql": f"""WITH (SELECT order_id FROM {D}.{STG}
       WHERE JSONLength(order_lines)>=3 AND order_status IN ({VALID}) LIMIT 1) AS pick
SELECT order_id, product_sku, product_name, unit_price, quantity, line_total
FROM {D}.{FCT} WHERE order_id=pick ORDER BY product_sku""",
    },
    {
        "id": "fanout",
        "label": "⑥ 주문당 라인 수 분포",
        "sql": f"""SELECT n_lines, count() AS orders FROM (
  SELECT order_id, count() AS n_lines FROM {D}.{FCT}
  WHERE product_sku!='' GROUP BY order_id) GROUP BY n_lines ORDER BY n_lines""",
    },
    {
        "id": "category",
        "label": "⑦ 카테고리별 매출",
        "sql": f"""SELECT product_category, count() AS line_items,
       sum(line_total) AS revenue, uniqExact(order_id) AS orders
FROM {D}.{FCT} WHERE order_date=today()
GROUP BY product_category ORDER BY revenue DESC""",
    },
    {
        "id": "tier",
        "label": "⑧ 등급별 객단가",
        "sql": f"""SELECT customer_tier, uniqExact(order_id) AS orders, sum(line_total) AS revenue,
       round(sum(line_total)/uniqExact(order_id),0) AS avg_order_value
FROM {D}.{FCT} GROUP BY customer_tier ORDER BY revenue DESC""",
    },
    {
        "id": "bestseller",
        "label": "⑨ 베스트셀러 TOP5",
        "sql": f"""SELECT product_name, sum(quantity) AS units, sum(line_total) AS revenue
FROM {D}.{FCT} GROUP BY product_name ORDER BY units DESC LIMIT 5""",
    },
    {
        "id": "explode_outer",
        "label": "⑩ explode_outer 검증",
        "sql": f"""SELECT order_status, countIf(product_sku='') AS empty_line_rows, count() AS total_rows
FROM {D}.{FCT} GROUP BY order_status ORDER BY order_status""",
    },
    {
        "id": "cancelled",
        "label": "⑪ cancelled 누락 검증(0이 정상)",
        "sql": f"""SELECT count() AS cancelled_leaked_into_fact FROM {D}.{FCT}
WHERE order_id IN (SELECT order_id FROM {D}.{STG} WHERE order_status IN ('cancelled','returned'))""",
    },
    {
        "id": "reconcile",
        "label": "⑫ 정합성 (staging=fact)",
        "sql": f"""SELECT (SELECT uniqExact(order_id) FROM {D}.{STG}
        WHERE order_status IN ({VALID})) AS staging_valid_orders,
       (SELECT uniqExact(order_id) FROM {D}.{FCT}) AS fact_orders""",
    },
    {
        "id": "parts",
        "label": "⑬ 파트 증가 관찰",
        "sql": f"""SELECT table, count() AS parts, sum(rows) AS rows,
       formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts WHERE database='{D}' AND active GROUP BY table ORDER BY table""",
    },
]

BY_ID = {p["id"]: p for p in PRESETS}
