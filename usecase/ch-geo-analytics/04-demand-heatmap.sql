-- ============================================================================
-- ch-geo-analytics Step 4: Demand Heatmap (Multi-Resolution H3 Aggregation)
-- ch-geo-analytics 4단계: 수요 히트맵 (다중 해상도 H3 집계)
-- ============================================================================
-- The killer feature: aggregating millions of points into a small number of
-- equal-area hexagonal cells. H3 cells make perfect GROUP BY keys for both
-- city-wide overviews (res 6) and surge-pricing precision (res 9-10).
-- 핵심 가치: 수백만 개의 좌표를 동일 면적의 hex 셀에 집계.
-- res 6은 도시 전체 한눈에, res 9-10은 서지 가격 정밀 분석에 적합.
-- ============================================================================

-- ============================================================================
-- 4.1 Top Pickup Hotspots (res 8, ~ block level)
-- 4.1 픽업 핫스팟 상위 (res 8, 블록 단위)
-- ============================================================================

SELECT
    h3ToString(pickup_h3_r8)                AS h3_hex,
    h3ToGeo(pickup_h3_r8).1                 AS center_lat,
    h3ToGeo(pickup_h3_r8).2                 AS center_lon,
    count()                                 AS pickups,
    round(avg(fare_amount), 2)              AS avg_fare,
    uniqExact(user_id)                      AS unique_riders
FROM   geo_analytics.trips
GROUP  BY pickup_h3_r8
ORDER  BY pickups DESC
LIMIT  10;

-- ============================================================================
-- 4.2 Coarser View: District-Level Demand (res 6)
-- 4.2 더 거친 시야: 지역구 단위 수요 (res 6)
-- ============================================================================

-- One row per ~3.2 km hex — small enough for a city-wide dashboard.
-- ~3.2km hex 단위 — 도시 전체 대시보드에 적합한 행 수
SELECT
    h3ToString(pickup_h3_r6) AS h3_hex,
    count()                  AS pickups,
    round(avg(fare_amount), 2) AS avg_fare
FROM   geo_analytics.trips
GROUP  BY pickup_h3_r6
ORDER  BY pickups DESC;

-- ============================================================================
-- 4.3 Roll Up via h3ToParent (Recommended Pattern)
-- 4.3 h3ToParent로 롤업 (권장 패턴)
-- ============================================================================

-- Store the finest resolution you need (e.g. r10) and roll up at query time.
-- 가장 세밀한 해상도(r10)만 저장하고 쿼리 시점에 롤업 — 멀티 줌 대시보드에 유용
SELECT
    target_resolution,
    uniqExact(target_hex) AS distinct_hexes
FROM (
    SELECT
        arrayJoin([5, 6, 7, 8, 9, 10])              AS target_resolution,
        h3ToParent(pickup_h3_r10, target_resolution) AS target_hex
    FROM geo_analytics.trips
)
GROUP BY target_resolution
ORDER BY target_resolution;

-- ============================================================================
-- 4.4 Hourly Demand by Hex (Time × Space)
-- 4.4 시간 × 공간 수요 (시간별 hex 수요)
-- ============================================================================

-- Top 5 hexes for each hour of the day — surge-pricing input.
-- 시간대별 상위 5개 hex — 서지 가격 산정 입력
SELECT
    hour_of_day,
    h3ToString(pickup_h3_r8) AS hex,
    pickups,
    rank
FROM (
    SELECT
        toHour(pickup_ts)    AS hour_of_day,
        pickup_h3_r8,
        count()              AS pickups,
        row_number() OVER (PARTITION BY toHour(pickup_ts) ORDER BY count() DESC) AS rank
    FROM   geo_analytics.trips
    GROUP  BY hour_of_day, pickup_h3_r8
)
WHERE rank <= 3
ORDER BY hour_of_day, rank;

-- ============================================================================
-- 4.5 Demand Drop-Off — Pickup vs. Dropoff Imbalance
-- 4.5 픽업 vs 드롭오프 불균형
-- ============================================================================

-- Hexes with more pickups than dropoffs are net "supply sinks" — drivers leave;
-- hexes with more dropoffs are net "supply sources" — drivers accumulate there.
-- 픽업 > 드롭오프 hex는 공급 부족 → 드라이버 유입 필요
-- 픽업 < 드롭오프 hex는 공급 과잉 → 차량이 쌓이는 지역
WITH pickups AS (
    SELECT pickup_h3_r8 AS hex, count() AS p_count
    FROM   geo_analytics.trips
    GROUP  BY pickup_h3_r8
),
dropoffs AS (
    SELECT dropoff_h3_r8 AS hex, count() AS d_count
    FROM   geo_analytics.trips
    GROUP  BY dropoff_h3_r8
)
SELECT
    h3ToString(p.hex)              AS hex,
    p.p_count                      AS pickups,
    coalesce(d.d_count, 0)         AS dropoffs,
    p.p_count - coalesce(d.d_count, 0) AS net_outflow
FROM   pickups p
LEFT   JOIN dropoffs d ON d.hex = p.hex
ORDER  BY abs(p.p_count - coalesce(d.d_count, 0)) DESC
LIMIT  10;

-- ============================================================================
-- 4.6 Daily Demand Heatmap (Date × Hex)
-- 4.6 일자 × hex 수요 히트맵
-- ============================================================================

SELECT
    toDate(pickup_ts)        AS day,
    h3ToString(pickup_h3_r6) AS hex,
    count()                  AS pickups
FROM   geo_analytics.trips
GROUP  BY day, pickup_h3_r6
ORDER  BY day, pickups DESC
LIMIT  20;

-- ============================================================================
-- 4.7 Top-N Hexes With Boundary Vertices (for Map Rendering)
-- 4.7 hex 경계 vertex 포함 (지도 렌더링용)
-- ============================================================================

-- h3ToGeoBoundary returns the 6 lat/lon vertices forming the hex outline,
-- ready to be sent to Leaflet / Mapbox / deck.gl as a polygon overlay.
-- h3ToGeoBoundary는 hex 외곽의 6개 정점 좌표를 반환 — Leaflet/Mapbox/deck.gl
-- 등에서 폴리곤 오버레이로 바로 사용 가능
SELECT
    h3ToString(pickup_h3_r8) AS hex,
    pickups,
    h3ToGeoBoundary(pickup_h3_r8) AS boundary_polygon
FROM (
    SELECT pickup_h3_r8, count() AS pickups
    FROM   geo_analytics.trips
    GROUP  BY pickup_h3_r8
    ORDER  BY pickups DESC
    LIMIT  5
)
FORMAT Vertical;

SELECT 'Step 4 complete. Next: 05-distance-and-routing.sql' AS done;
