-- ============================================================================
-- ch-geo-analytics Step 7: H3 vs Geohash vs S2 — Indexing System Comparison
-- ch-geo-analytics 7단계: H3 vs Geohash vs S2 인덱싱 체계 비교
-- ============================================================================
-- ClickHouse natively supports three spatial discretization systems:
--   1. H3      — hexagonal,  64-bit integer index, 16 resolutions  (Uber)
--   2. Geohash — string-based, base-32, longer string = finer grid (Niemeyer 2008)
--   3. S2      — quadrilateral, 64-bit cell ID, 30 levels         (Google)
--
-- This step compares them side-by-side on the same NYC trip data so you can
-- pick the right tool for a given workload.
-- ClickHouse는 3가지 공간 분할 체계를 모두 지원:
--   1. H3      — 육각형, UInt64 인덱스, 16단계 해상도 (Uber)
--   2. Geohash — 문자열, base32 인코딩, 문자열이 길수록 세밀 (Niemeyer 2008)
--   3. S2      — 사각형, UInt64 셀 ID, 30단계 (Google)
-- ============================================================================

-- ============================================================================
-- 7.1 Side-by-Side Encoding of the Same Point
-- 7.1 동일한 좌표를 세 가지 체계로 인코딩
-- ============================================================================

WITH -73.9857 AS lon, 40.7484 AS lat
SELECT
    'Times Square'                              AS location,
    geoToH3(lon, lat, 8)                        AS h3_uint64,
    h3ToString(geoToH3(lon, lat, 8))            AS h3_hex,
    geohashEncode(lon, lat, 7)                  AS geohash_7,
    geohashEncode(lon, lat, 9)                  AS geohash_9,
    geoToS2(lon, lat)                           AS s2_cell_id;

-- ============================================================================
-- 7.2 Cardinality / Coverage Comparison on Real Data
-- 7.2 실제 데이터에서 cardinality / coverage 비교
-- ============================================================================

-- How many distinct cells does each system produce for our 5M trips?
-- 5M 트립이 각 체계에서 몇 개의 distinct 셀로 분류되는지 비교
SELECT * FROM (
    SELECT 'H3 res 6'              AS encoding, uniqExact(pickup_h3_r6)                              AS distinct_cells FROM geo_analytics.trips
    UNION ALL SELECT 'H3 res 8',               uniqExact(pickup_h3_r8)                                                FROM geo_analytics.trips
    UNION ALL SELECT 'H3 res 10',              uniqExact(pickup_h3_r10)                                               FROM geo_analytics.trips
    UNION ALL SELECT 'Geohash p=5 (~5 km)',    uniqExact(geohashEncode(pickup_lon, pickup_lat, 5))                    FROM geo_analytics.trips
    UNION ALL SELECT 'Geohash p=7 (~150 m)',   uniqExact(geohashEncode(pickup_lon, pickup_lat, 7))                    FROM geo_analytics.trips
    UNION ALL SELECT 'Geohash p=9 (~5 m)',     uniqExact(geohashEncode(pickup_lon, pickup_lat, 9))                    FROM geo_analytics.trips
    UNION ALL SELECT 'S2',                     uniqExact(geoToS2(pickup_lon, pickup_lat))                             FROM geo_analytics.trips
)
ORDER BY encoding;

-- ============================================================================
-- 7.3 Geohash Aggregation
-- 7.3 Geohash 집계
-- ============================================================================

-- Top pickup geohashes at precision 7 (~150 m grid)
-- 정밀도 7 (~150 m) geohash 픽업 상위
SELECT
    geohashEncode(pickup_lon, pickup_lat, 7) AS geohash,
    count()                                   AS pickups,
    round(avg(fare_amount), 2)                AS avg_fare
FROM   geo_analytics.trips
GROUP  BY geohash
ORDER  BY pickups DESC
LIMIT  10;

-- Decoding a geohash back to its bounding box
-- geohash를 다시 bounding box 좌표로 디코딩
SELECT
    geohashEncode(-73.9857, 40.7484, 7) AS gh,
    geohashDecode(geohashEncode(-73.9857, 40.7484, 7)) AS center_lon_lat_box;

-- ============================================================================
-- 7.4 geohashesInBox — All Geohash Cells Covering a Bounding Box
-- 7.4 geohashesInBox — Bounding box를 덮는 모든 geohash 셀
-- ============================================================================

-- All precision-7 geohashes covering a 0.01° × 0.01° box around Times Square.
-- Useful for filtering by spatial extent without computing every cell ID.
-- 타임스퀘어 주변 0.01° × 0.01° 박스를 덮는 정밀도 7 geohash 리스트.
-- 공간 필터를 cell ID 일일이 계산하지 않고 빠르게 처리 가능.
SELECT
    length(geohashesInBox(
        -73.99, 40.74,  -- lon_min, lat_min
        -73.98, 40.75,  -- lon_max, lat_max
        7
    )) AS geohash_count_in_box;

-- ============================================================================
-- 7.5 H3 vs Geohash vs S2 — Aggregation Performance on the Same Question
-- 7.5 동일한 질문을 H3 / Geohash / S2로 집계 — 성능 / 결과 비교
-- ============================================================================

-- "Top 5 cells by pickup count" computed three ways.
-- The H3 query uses the MATERIALIZED column (pre-computed at INSERT time)
-- while geohash/S2 are computed on the fly.
-- "픽업 상위 5개 셀"을 세 가지 방식으로 계산.
-- H3는 MATERIALIZED 컬럼을 사용 (적재 시점에 미리 계산)
-- Geohash/S2는 쿼리 시점에 계산
SELECT 'H3 res 8 (pre-computed)' AS method, * FROM (
    SELECT h3ToString(pickup_h3_r8) AS cell, count() AS pickups
    FROM geo_analytics.trips
    GROUP BY pickup_h3_r8
    ORDER BY pickups DESC LIMIT 5
)
UNION ALL
SELECT 'Geohash p=7 (on the fly)' AS method, cell, pickups FROM (
    SELECT geohashEncode(pickup_lon, pickup_lat, 7) AS cell, count() AS pickups
    FROM geo_analytics.trips
    GROUP BY cell
    ORDER BY pickups DESC LIMIT 5
)
UNION ALL
SELECT 'S2 (on the fly)' AS method, toString(cell) AS cell, pickups FROM (
    SELECT geoToS2(pickup_lon, pickup_lat) AS cell, count() AS pickups
    FROM geo_analytics.trips
    GROUP BY cell
    ORDER BY pickups DESC LIMIT 5
)
ORDER BY method;

-- ============================================================================
-- 7.6 Trade-Offs Summary
-- 7.6 트레이드오프 요약
-- ============================================================================

SELECT
    system,
    cell_shape,
    storage_type,
    hierarchical,
    equal_area,
    best_for
FROM (
    SELECT
        'H3'      AS system,
        'Hexagon' AS cell_shape,
        'UInt64'  AS storage_type,
        'Yes (16 levels)'   AS hierarchical,
        'Yes (almost)'      AS equal_area,
        'Mobility, demand heatmaps, k-ring neighbor analysis' AS best_for
    UNION ALL SELECT
        'Geohash', 'Rectangle', 'String (var length)',
        'Yes (prefix nesting)', 'No (varies by latitude)',
        'String prefix searches, easy URL params, geocoding APIs'
    UNION ALL SELECT
        'S2',      'Quadrilateral', 'UInt64',
        'Yes (30 levels)', 'Yes (within tolerance)',
        'Global services, coverage / containment via Hilbert curve'
) ORDER BY system;

SELECT 'Step 7 complete. Next: 08-materialized-views.sql' AS done;
