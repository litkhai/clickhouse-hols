-- ============================================================================
-- ch-geo-analytics Step 3: H3 Fundamentals
-- ch-geo-analytics 3단계: H3 인덱싱 기본
-- ============================================================================
-- H3 is Uber's hexagonal hierarchical spatial index. Each H3 index is a single
-- UInt64 representing a hexagonal cell at one of 16 resolutions (0 = ~1100 km
-- edge, 15 = ~50 cm edge). Hexagons tile the sphere with equal-area cells
-- (with 12 pentagonal cells per resolution to handle curvature).
-- H3는 Uber가 만든 육각형 계층 공간 인덱스입니다. 각 H3 인덱스는 UInt64 한 개로
-- 표현되며 0(~1100km 엣지)부터 15(~50cm 엣지)까지 16단계 해상도가 있습니다.
-- ============================================================================

-- ============================================================================
-- 3.1 Hex Index Encoding
-- 3.1 Hex 인덱스 인코딩
-- ============================================================================

-- A lon/lat pair → a single UInt64 H3 index at a chosen resolution.
-- 경도/위도 → 선택한 해상도의 UInt64 H3 인덱스로 변환
SELECT
    'Times Square @ res 8'                    AS location,
    geoToH3(-73.9857, 40.7484, 8)             AS h3_index_uint64,
    h3ToString(geoToH3(-73.9857, 40.7484, 8)) AS h3_index_hex_string;

-- Round-trip back to the *center* of the hex.
-- (Not the original lat/lon — every coordinate that falls in the same hex
--  decodes back to the same hex-center point.)
-- 인덱스를 다시 디코딩하면 hex의 중심점 좌표가 나옵니다.
-- (원본 좌표가 아니라, 같은 hex에 떨어진 모든 좌표는 동일한 중심점으로 디코딩됨.)
SELECT
    h3ToGeo(geoToH3(-73.9857, 40.7484, 8)) AS hex_center;

-- ============================================================================
-- 3.2 Resolution Reference Table
-- 3.2 해상도 레퍼런스 테이블
-- ============================================================================

-- Average hex edge length and area per resolution. As resolution increases by 1,
-- the hex area shrinks by roughly 7x (since 1 parent hex ≈ 7 children).
-- 해상도가 1 증가할 때마다 hex 면적은 약 7배 작아집니다 (1 parent ≈ 7 child).
SELECT
    resolution,
    round(h3EdgeLengthM(resolution), 1)                   AS edge_length_m,
    round(h3HexAreaM2(resolution), 1)                     AS area_m2,
    formatReadableSize(toUInt64(h3HexAreaM2(resolution))) AS area_pretty
FROM   (SELECT arrayJoin([0, 4, 6, 7, 8, 9, 10, 12, 15]) AS resolution)
ORDER  BY resolution;

-- ============================================================================
-- 3.3 Hierarchy — Parent and Children
-- 3.3 계층 구조 - 부모와 자식
-- ============================================================================

-- A res-8 hex has one parent at res 6 and ~49 children at res 10.
-- res 8 hex 한 개는 res 6에 부모 1개, res 10에 ~49개 자식을 가짐
WITH geoToH3(-73.9857, 40.7484, 8) AS hex8
SELECT
    hex8                              AS hex_res8,
    h3GetResolution(hex8)             AS resolution,
    h3ToParent(hex8, 6)               AS parent_res6,
    length(h3ToChildren(hex8, 9))     AS num_children_res9,
    length(h3ToChildren(hex8, 10))    AS num_children_res10;

-- ============================================================================
-- 3.4 K-Ring Neighbors
-- 3.4 K-Ring 이웃
-- ============================================================================

-- Hexagons within k rings of a center hex. Used heavily in "find demand
-- around hotspot X within ~Y meters" queries.
-- 중심 hex에서 k링 내부의 모든 hex. "핫스팟 주변 N미터 안의 수요" 같은 쿼리에 사용.
SELECT
    k                              AS k_rings,
    length(h3kRing(
        geoToH3(-73.9857, 40.7484, 8),
        k
    ))                             AS observed_count,
    3 * k * k + 3 * k + 1          AS theoretical_count  -- = 1 + 6 + 12 + ... + 6k
FROM   (SELECT arrayJoin([0, 1, 2, 3, 5, 10]) AS k)
ORDER  BY k;

-- ============================================================================
-- 3.5 Distance Between Hexes
-- 3.5 Hex 간 거리
-- ============================================================================

-- h3Distance returns grid distance in hex steps (not meters).
-- h3PointDistM takes lat/lon (NOT lon/lat) — note the argument order difference
-- vs. greatCircleDistance.
-- h3Distance: hex 단위 거리. h3PointDistM 인자 순서는 (위도, 경도, 위도, 경도)로
-- greatCircleDistance(경도, 위도, ...)와 다릅니다.
WITH geoToH3(-73.9857, 40.7484, 8) AS times_sq_hex,
     geoToH3(-73.9772, 40.7527, 8) AS grand_central_hex
SELECT
    h3Distance(times_sq_hex, grand_central_hex)        AS hex_steps,
    round(h3PointDistM(
        40.7484, -73.9857,   -- (lat1, lon1)
        40.7527, -73.9772    -- (lat2, lon2)
    ), 0)                                              AS meters_between_centers,
    round(greatCircleDistance(
        -73.9857, 40.7484,   -- (lon1, lat1)
        -73.9772, 40.7527    -- (lon2, lat2)
    ), 0)                                              AS great_circle_m;

-- ============================================================================
-- 3.6 Validation
-- 3.6 유효성 검사
-- ============================================================================

SELECT
    h3IsValid(geoToH3(-73.9857, 40.7484, 8)) AS valid_h3,
    h3IsValid(toUInt64(12345))               AS zero_is_invalid,
    h3IsPentagon(geoToH3(-73.9857, 40.7484, 8)) AS is_pentagon,
    h3GetBaseCell(geoToH3(-73.9857, 40.7484, 8)) AS base_cell;

-- ============================================================================
-- 3.7 Use the MATERIALIZED H3 Columns From the trips Table
-- 3.7 트립 테이블의 MATERIALIZED H3 컬럼 활용
-- ============================================================================

-- Show the same pickup location indexed at multiple resolutions.
-- 동일한 픽업 좌표를 여러 해상도로 인덱싱한 결과
SELECT
    pickup_lon,
    pickup_lat,
    h3ToString(pickup_h3_r6)  AS r6_hex,
    h3ToString(pickup_h3_r8)  AS r8_hex,
    h3ToString(pickup_h3_r10) AS r10_hex,
    h3GetResolution(pickup_h3_r6)  AS r6,
    h3GetResolution(pickup_h3_r8)  AS r8,
    h3GetResolution(pickup_h3_r10) AS r10
FROM   geo_analytics.trips
LIMIT  3
FORMAT Vertical;

-- Hierarchy quirk: H3's parent/child nesting is *approximate*. The res-10 hex
-- of a raw point does NOT always have the res-8 hex of that same raw point as
-- its h3ToParent — they can disagree near hex boundaries. For consistent
-- roll-ups, always derive coarser hexes via h3ToParent() of the finest one,
-- never re-encode the raw lat/lon at multiple resolutions.
-- H3 계층은 *근사적*입니다. 동일한 raw 좌표를 r10과 r8로 따로 인코딩하면
-- 경계 근처에서 h3ToParent(r10, 8) ≠ r8 가 될 수 있습니다.
-- 일관된 롤업을 위해서는 가장 세밀한 해상도만 저장하고, 더 거친 해상도는
-- h3ToParent()로 유도해서 사용하는 것이 권장됩니다.
SELECT
    countIf(h3ToParent(pickup_h3_r10, 8) = pickup_h3_r8) AS r10_to_r8_match,
    countIf(h3ToParent(pickup_h3_r8,  6) = pickup_h3_r6) AS r8_to_r6_match,
    count()                                              AS total_trips,
    round(100.0 *
        countIf(h3ToParent(pickup_h3_r10, 8) = pickup_h3_r8) / count(), 2)
                                                         AS r10_to_r8_pct
FROM   geo_analytics.trips;

SELECT 'Step 3 complete. Next: 04-demand-heatmap.sql' AS done;
