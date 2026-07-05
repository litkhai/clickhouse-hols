"""우측 하단 프리셋 쿼리 — 3개 카테고리로 분류 + 각 쿼리에 의미(desc) 부여.

  A. 상태 모니터링   — 파이프라인이 살아있고 정합적인가
  B. 성능 관련 지표   — parts / 압축률 / 저장 구조
  C. 비즈니스 집계    — 평탄화된 fact 로 뽑는 실무 지표
"""
from config import CFG

D = CFG.database
RAW, STG, FCT = CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact
ERR = f"{RAW}_clickpipes_error"
VALID = CFG.valid_statuses_sql()

# category 순서 고정
CATEGORIES = ["상태 모니터링", "성능 관련 지표", "비즈니스 집계 지표"]

PRESETS = [
    # ─────────────── A. 상태 모니터링 ───────────────
    {
        "id": "counts", "category": "상태 모니터링",
        "label": "파이프라인 행 수",
        "desc": "raw→staging→fact 각 단계의 건수. raw=staging 이고 fact 가 더 크면(=explode) 정상.",
        "sql": f"""SELECT (SELECT count() FROM {D}.{RAW}) AS raw_rows,
       (SELECT count() FROM {D}.{STG}) AS staging_rows,
       (SELECT count() FROM {D}.{FCT}) AS fact_lines""",
    },
    {
        "id": "freshness", "category": "상태 모니터링",
        "label": "각 단계 최신성",
        "desc": "단계별 마지막 도착 시각. 세 값이 현재와 가까우면 파이프라인이 실시간으로 흐르는 것.",
        "sql": f"""SELECT stage, last_seen FROM (
  SELECT 'raw' AS stage, toDateTime(max(_ingested_at)) AS last_seen FROM {D}.{RAW}
  UNION ALL SELECT 'staging', toDateTime(max(_timestamp)) FROM {D}.{STG}
  UNION ALL SELECT 'fact', toDateTime(max(order_timestamp_local)) FROM {D}.{FCT}
) ORDER BY stage""",
    },
    {
        "id": "status_dist", "category": "상태 모니터링",
        "label": "상태별 주문 분포",
        "desc": "staging 의 order_status 분포. cancelled/returned 도 여기엔 있지만 fact 엔 없어야 함.",
        "sql": f"""SELECT order_status, count() AS orders
FROM {D}.{STG} GROUP BY order_status ORDER BY orders DESC""",
    },
    {
        "id": "beforeafter", "category": "상태 모니터링",
        "label": "변환 before/after",
        "desc": "같은 주문의 raw vs staging. placeholder id→NULL, tracking 대체, UTC→로컬 변환 확인.",
        "sql": f"""SELECT r.customer_id AS raw_customer_id, s.customer_id AS clean_customer_id,
       s.tracking_id, r.created_at AS raw_utc, s.order_timestamp_local AS local_kst
FROM {D}.{RAW} r INNER JOIN {D}.{STG} s USING (order_id)
ORDER BY s._timestamp DESC LIMIT 12""",
    },
    {
        "id": "nullfix", "category": "상태 모니터링",
        "label": "NULL 치환 효과",
        "desc": "placeholder((not set)/undefined/'')가 실제로 몇 건이나 NULL 로 정리됐는지.",
        "sql": f"""SELECT countIf(customer_id IS NULL) AS null_customers,
       countIf(customer_id IS NOT NULL) AS real_customers, count() AS total
FROM {D}.{STG}""",
    },
    {
        "id": "explode_outer", "category": "상태 모니터링",
        "label": "explode_outer 검증",
        "desc": "빈 배열 주문도 row 로 유지되는지(product_sku='' 인 행). 데이터 유실 없음 증명.",
        "sql": f"""SELECT order_status, countIf(product_sku='') AS empty_line_rows, count() AS total_rows
FROM {D}.{FCT} GROUP BY order_status ORDER BY order_status""",
    },
    {
        "id": "cancelled", "category": "상태 모니터링",
        "label": "cancelled 누락 검증",
        "desc": "cancelled/returned 주문이 fact 로 새지 않았는지. 0 이면 상태 필터 정상.",
        "sql": f"""SELECT count() AS cancelled_leaked_into_fact FROM {D}.{FCT}
WHERE order_id IN (SELECT order_id FROM {D}.{STG} WHERE order_status IN ('cancelled','returned'))""",
    },
    {
        "id": "reconcile", "category": "상태 모니터링",
        "label": "정합성 (staging=fact)",
        "desc": "staging 유효 주문 수 == fact 고유 주문 수. 두 값이 같으면 explode 손실/중복 없음.",
        "sql": f"""SELECT (SELECT uniqExact(order_id) FROM {D}.{STG}
        WHERE order_status IN ({VALID})) AS staging_valid_orders,
       (SELECT uniqExact(order_id) FROM {D}.{FCT}) AS fact_orders""",
    },

    # ─────────────── B. 성능 관련 지표 ───────────────
    {
        "id": "objects", "category": "성능 관련 지표",
        "label": "오브젝트 현황",
        "desc": "테이블/MV 엔진·행수·압축 크기 개요. MergeTree 계열 + MaterializedView 구성 확인.",
        "sql": f"""SELECT name, engine, total_rows, formatReadableSize(total_bytes) AS size
FROM system.tables WHERE database='{D}' ORDER BY name""",
    },
    {
        "id": "parts", "category": "성능 관련 지표",
        "label": "파트(parts) 현황",
        "desc": "테이블별 활성 파트 수·행수·크기·파트당 평균 행. 삽입이 많으면 파트가 늘고, 병합이 줄임.",
        "sql": f"""SELECT table, count() AS parts, sum(rows) AS total_rows,
       formatReadableSize(sum(bytes_on_disk)) AS size,
       round(avg(rows)) AS avg_rows_per_part
FROM system.parts WHERE database='{D}' AND active
GROUP BY table ORDER BY table""",
    },
    {
        "id": "compression", "category": "성능 관련 지표",
        "label": "압축률",
        "desc": "테이블별 압축 전/후 크기와 압축비. 컬럼형 저장의 효율을 한눈에(높을수록 좋음).",
        "sql": f"""SELECT table,
       formatReadableSize(sum(data_compressed_bytes))   AS compressed,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
       round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 1) AS ratio
FROM system.parts WHERE database='{D}' AND active
GROUP BY table ORDER BY table""",
    },
    {
        "id": "columns", "category": "성능 관련 지표",
        "label": "컬럼별 저장 크기 (fact)",
        "desc": "fact 테이블에서 어떤 컬럼이 저장을 많이 쓰는지 TOP10. LowCardinality/타입 선택의 효과.",
        "sql": f"""SELECT column,
       formatReadableSize(sum(column_data_compressed_bytes))   AS compressed,
       formatReadableSize(sum(column_data_uncompressed_bytes)) AS uncompressed
FROM system.parts_columns
WHERE database='{D}' AND table='{FCT}' AND active
GROUP BY column ORDER BY sum(column_data_compressed_bytes) DESC LIMIT 10""",
    },

    # ─────────────── C. 비즈니스 집계 지표 ───────────────
    {
        "id": "category", "category": "비즈니스 집계 지표",
        "label": "카테고리별 매출",
        "desc": "오늘 카테고리별 라인 수·매출·주문 수. 평탄화 덕에 상품 단위 집계가 바로 가능.",
        "sql": f"""SELECT product_category, count() AS line_items,
       sum(line_total) AS revenue, uniqExact(order_id) AS orders
FROM {D}.{FCT} WHERE order_date=today()
GROUP BY product_category ORDER BY revenue DESC""",
    },
    {
        "id": "tier", "category": "비즈니스 집계 지표",
        "label": "등급별 객단가",
        "desc": "고객 등급(tier)별 주문 수·매출·평균 주문금액(AOV). 세그먼트 가치 비교.",
        "sql": f"""SELECT customer_tier, uniqExact(order_id) AS orders, sum(line_total) AS revenue,
       round(sum(line_total)/uniqExact(order_id), 0) AS avg_order_value
FROM {D}.{FCT} GROUP BY customer_tier ORDER BY revenue DESC""",
    },
    {
        "id": "bestseller", "category": "비즈니스 집계 지표",
        "label": "베스트셀러 TOP5",
        "desc": "판매 수량 기준 상위 상품. line 단위로 펼쳐졌기에 quantity 합산이 자연스러움.",
        "sql": f"""SELECT product_name, sum(quantity) AS units, sum(line_total) AS revenue
FROM {D}.{FCT} GROUP BY product_name ORDER BY units DESC LIMIT 5""",
    },
    {
        "id": "trend", "category": "비즈니스 집계 지표",
        "label": "분당 주문 추이",
        "desc": "분 단위 주문·매출 추이. producer 를 켜두면 최신 분의 숫자가 실시간으로 쌓임.",
        "sql": f"""SELECT toStartOfMinute(order_timestamp_local) AS minute,
       uniqExact(order_id) AS orders, sum(line_total) AS revenue
FROM {D}.{FCT} GROUP BY minute ORDER BY minute DESC LIMIT 10""",
    },
    {
        "id": "fanout", "category": "비즈니스 집계 지표",
        "label": "주문당 라인 수 분포",
        "desc": "주문 하나에 상품이 몇 개 담기는지 분포. explode 의 fan-out 규모를 시각화.",
        "sql": f"""SELECT n_lines, count() AS orders FROM (
  SELECT order_id, count() AS n_lines FROM {D}.{FCT}
  WHERE product_sku!='' GROUP BY order_id) GROUP BY n_lines ORDER BY n_lines""",
    },
    {
        "id": "explode", "category": "비즈니스 집계 지표",
        "label": "장바구니 구성 예시",
        "desc": "라인 3개 이상 주문 하나를 골라 fact 에서 펼쳐진 모습. 1 주문 → N 상품 행.",
        "sql": f"""WITH (SELECT order_id FROM {D}.{STG}
       WHERE JSONLength(order_lines)>=3 AND order_status IN ({VALID}) LIMIT 1) AS pick
SELECT order_id, product_sku, product_name, unit_price, quantity, line_total
FROM {D}.{FCT} WHERE order_id=pick ORDER BY product_sku""",
    },
]

BY_ID = {p["id"]: p for p in PRESETS}


def grouped():
    """카테고리 순서대로 [{category, items:[{id,label,desc,sql}]}] 반환."""
    out = []
    for cat in CATEGORIES:
        items = [{"id": p["id"], "label": p["label"], "desc": p["desc"], "sql": p["sql"]}
                 for p in PRESETS if p["category"] == cat]
        out.append({"category": cat, "items": items})
    return out
