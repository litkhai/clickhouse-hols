-- ============================================================================
-- ch-geo-analytics Step 6: Spatial Search (K-Ring, Point-in-Polygon)
-- ch-geo-analytics 6단계: 공간 검색 (K-Ring, 점-폴리곤 포함)
-- ============================================================================
-- The two big spatial-search building blocks in ClickHouse:
--   1. H3 k-ring  → "find all points within ~K hex steps of a center"
--   2. pointInPolygon → "find all points inside an arbitrary polygon"
-- ClickHouse 공간 검색의 두 가지 큰 빌딩 블록:
--   1. H3 k-ring → "중심점에서 ~K hex 단계 이내의 점들"
--   2. pointInPolygon → "임의의 폴리곤 내부 점들"
-- ============================================================================

-- ============================================================================
-- 6.1 K-Ring Demand Around Times Square
-- 6.1 타임스퀘어 주변 K-Ring 수요
-- ============================================================================

-- All trips within k=2 hex rings (~ 1 km radius at res 8) of Times Square.
-- Two patterns:
--   (a) IN-list of hexes — fast, uses sparse index
--   (b) h3Distance() filter — clearer but full-scan
-- 타임스퀘어 중심에서 k=2 (≈ 1 km) 이내의 트립
-- (a) hex IN 리스트 — sparse 인덱스 활용, 빠름
-- (b) h3Distance() 필터 — 가독성은 좋지만 full-scan
WITH
    geoToH3(-73.9857, 40.7580, 8)             AS times_sq,
    h3kRing(times_sq, 2)                      AS nearby_hexes
SELECT
    'k-ring IN-list' AS strategy,
    count()          AS trips,
    round(avg(fare_amount), 2) AS avg_fare,
    length(nearby_hexes) AS hexes_in_filter
FROM   geo_analytics.trips
WHERE  pickup_h3_r8 IN nearby_hexes;

-- Equivalent via h3Distance — same result, different access pattern
-- h3Distance를 쓴 동일한 쿼리 — 결과는 같지만 접근 패턴이 다름
WITH geoToH3(-73.9857, 40.7580, 8) AS times_sq
SELECT
    'h3Distance filter' AS strategy,
    count()             AS trips,
    round(avg(fare_amount), 2) AS avg_fare
FROM   geo_analytics.trips
WHERE  h3Distance(pickup_h3_r8, times_sq) <= 2;

-- ============================================================================
-- 6.2 Comparing K-Ring Sizes (find the right radius)
-- 6.2 K-Ring 크기 비교 (적절한 반경 찾기)
-- ============================================================================

-- Sweep k = 0..5 to see how demand grows with radius around JFK Airport.
-- JFK 공항 중심으로 k=0~5을 스윕해 반경별 수요 증가를 관찰
WITH geoToH3(-73.7781, 40.6413, 8) AS jfk_hex
SELECT
    k,
    length(h3kRing(jfk_hex, k))    AS hex_count_in_filter,
    -- 1 hex_step ≈ h3EdgeLengthM(8) meters
    round(k * h3EdgeLengthM(8), 0) AS approx_radius_m,
    (
        SELECT count()
        FROM   geo_analytics.trips
        WHERE  pickup_h3_r8 IN h3kRing(jfk_hex, k)
    )                              AS trips_in_filter
FROM   (SELECT arrayJoin([0, 1, 2, 3, 5]) AS k);

-- ============================================================================
-- 6.3 Point-in-Polygon: Service-Zone Tagging
-- 6.3 점-폴리곤 포함: 서비스 존 태깅
-- ============================================================================

-- Count trips that started inside each pre-defined service zone polygon.
-- 미리 정의된 서비스 존 폴리곤 내부에서 시작한 트립 수를 카운트
SELECT
    z.zone_name,
    z.borough,
    count() AS pickups_in_zone,
    round(avg(t.fare_amount), 2) AS avg_fare
FROM   geo_analytics.trips    AS t
INNER  JOIN geo_analytics.service_zones AS z
    ON pointInPolygon((t.pickup_lon, t.pickup_lat), z.polygon)
GROUP  BY z.zone_id, z.zone_name, z.borough
ORDER  BY pickups_in_zone DESC;

-- ============================================================================
-- 6.4 Cross-Zone OD (Origin-Destination) Matrix
-- 6.4 존 간 OD 매트릭스 (출발-도착)
-- ============================================================================

-- For each (pickup_zone, dropoff_zone) pair, how many trips and what fare?
-- This is THE classic mobility-analytics output.
-- (픽업 존, 드롭오프 존) 쌍별 트립 수와 요금 — 모빌리티 분석의 고전적 결과물
WITH
    trips_with_zones AS (
        SELECT
            t.trip_id,
            t.fare_amount,
            zo.zone_name AS origin_zone,
            zd.zone_name AS dest_zone
        FROM   geo_analytics.trips         AS t
        INNER  JOIN geo_analytics.service_zones AS zo
            ON pointInPolygon((t.pickup_lon,  t.pickup_lat),  zo.polygon)
        INNER  JOIN geo_analytics.service_zones AS zd
            ON pointInPolygon((t.dropoff_lon, t.dropoff_lat), zd.polygon)
    )
SELECT
    origin_zone,
    dest_zone,
    count()                    AS trips,
    round(avg(fare_amount), 2) AS avg_fare
FROM   trips_with_zones
GROUP  BY origin_zone, dest_zone
ORDER  BY trips DESC
LIMIT  15;

-- ============================================================================
-- 6.5 H3 Polygon Fill — "Which hexes cover a polygon?"
-- 6.5 H3 폴리곤 채우기 — "이 폴리곤을 덮는 hex 들은?"
-- ============================================================================

-- h3PolygonToCells(polygon, resolution) returns the hex indexes covering the
-- given polygon. Two gotchas to remember:
--   1. The polygon must be an UNNAMED Array(Tuple(Float64, Float64)).
--   2. The tuple order is (LAT, LON) — opposite of geoToH3(lon, lat, res) and
--      pointInPolygon((lon, lat), poly). If you store polygons as (lon, lat),
--      swap on the way in with arrayMap(p -> (p.2, p.1), polygon).
-- h3PolygonToCells(폴리곤, 해상도): 폴리곤을 덮는 hex 인덱스 배열을 반환.
-- 주의사항:
--   1. 폴리곤은 UNNAMED Tuple 배열이어야 함.
--   2. 인자 순서가 (위도, 경도)로, geoToH3(경도, 위도, 해상도) 및
--      pointInPolygon((경도, 위도), poly)와 정반대.
--      컬럼이 (경도, 위도)면 arrayMap(p -> (p.2, p.1), polygon)으로 swap 필수.
SELECT
    zone_name,
    length(h3PolygonToCells(arrayMap(p -> (p.2, p.1), polygon), 8)) AS hex_count_at_res8,
    length(h3PolygonToCells(arrayMap(p -> (p.2, p.1), polygon), 9)) AS hex_count_at_res9
FROM   geo_analytics.service_zones
ORDER  BY zone_id;

-- ============================================================================
-- 6.6 Hybrid Pre-Filter — h3PolygonToCells → IN ()
-- 6.6 하이브리드 사전 필터 — h3PolygonToCells → IN ()
-- ============================================================================

-- Instead of running pointInPolygon on every trip (CPU-heavy), first
-- precompute the hex cells covering the polygon and filter by hex IN-list.
-- Then refine with pointInPolygon on the survivors to handle edge cases.
-- pointInPolygon을 모든 트립에 실행하는 대신, 폴리곤을 덮는 hex를 미리
-- 계산해 hex IN-list로 1차 필터 → 후보에 대해서만 pointInPolygon으로 정밀 검증.
WITH
    (SELECT h3PolygonToCells(arrayMap(p -> (p.2, p.1), polygon), 8) FROM geo_analytics.service_zones WHERE zone_name = 'JFK Airport Zone') AS jfk_hexes,
    (SELECT polygon                                                 FROM geo_analytics.service_zones WHERE zone_name = 'JFK Airport Zone') AS jfk_polygon
SELECT
    count() AS trips_inside_jfk_zone,
    round(avg(fare_amount), 2) AS avg_fare
FROM   geo_analytics.trips
WHERE  pickup_h3_r8 IN jfk_hexes
  AND  pointInPolygon((pickup_lon, pickup_lat), jfk_polygon);

-- ============================================================================
-- 6.7 H3 Line — Hex Path Between Two Points
-- 6.7 H3 Line — 두 점 사이의 hex 경로
-- ============================================================================

-- h3Line returns the straight-line sequence of hexes between two endpoints.
-- Useful for visualizing routes or constructing path-based aggregates.
-- h3Line: 두 hex 사이의 직선 경로 hex 시퀀스 반환 — 경로 시각화/집계에 유용
SELECT
    h3Line(
        geoToH3(-73.9857, 40.7580, 8),  -- Times Square
        geoToH3(-73.7781, 40.6413, 8)   -- JFK Airport
    ) AS times_sq_to_jfk_hex_path,
    length(h3Line(
        geoToH3(-73.9857, 40.7580, 8),
        geoToH3(-73.7781, 40.6413, 8)
    )) AS hex_steps;

SELECT 'Step 6 complete. Next: 07-indexing-systems.sql' AS done;
