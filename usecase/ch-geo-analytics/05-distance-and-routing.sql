-- ============================================================================
-- ch-geo-analytics Step 5: Distance, Routing & Trip Length Analytics
-- ch-geo-analytics 5단계: 거리, 라우팅, 운행 길이 분석
-- ============================================================================
-- ClickHouse provides three families of distance functions:
--   - greatCircleDistance(lon1, lat1, lon2, lat2)    — sphere assumption, fastest
--   - geoDistance(lon1, lat1, lon2, lat2)            — WGS84 ellipsoid, more accurate
--   - h3PointDistM(lat1, lon1, lat2, lon2)           — center-to-center via H3
--   - h3Distance(h3a, h3b)                           — hex-grid steps (integer)
-- ClickHouse 거리 함수 종류:
--   - greatCircleDistance: 구체 가정, 가장 빠름
--   - geoDistance: WGS84 타원체, 더 정확함
--   - h3PointDistM: hex 중심점 간 거리
--   - h3Distance: hex 그리드 단위 거리 (정수)
-- ============================================================================

-- ============================================================================
-- 5.1 Trip Length Distribution
-- 5.1 운행 거리 분포
-- ============================================================================

-- Compute the great-circle pickup→dropoff distance once and bucket it.
-- 픽업→드롭오프 대권 거리를 계산하고 버킷화
SELECT
    multiIf(
        dist_m <   500,  '1: < 0.5 km',
        dist_m <  2000,  '2: 0.5 – 2 km',
        dist_m <  5000,  '3: 2 – 5 km',
        dist_m < 10000,  '4: 5 – 10 km',
        dist_m < 20000,  '5: 10 – 20 km',
        '6: > 20 km'
    )                              AS distance_bucket,
    count()                        AS trips,
    round(avg(fare_amount), 2)     AS avg_fare,
    round(avg(dist_m), 0)          AS avg_meters
FROM (
    SELECT
        fare_amount,
        greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) AS dist_m
    FROM geo_analytics.trips
)
GROUP BY distance_bucket
ORDER BY distance_bucket;

-- ============================================================================
-- 5.2 Great-Circle vs WGS84 Geo-Distance Comparison
-- 5.2 대권 거리 vs WGS84 정확 거리 비교
-- ============================================================================

-- At city scale the difference is tiny but non-zero. Use geoDistance when
-- absolute accuracy matters (legal fare audits, regulatory reporting).
-- 도시 규모에서는 차이가 작지만 0이 아닙니다. 정확성이 중요할 때 geoDistance 사용
SELECT
    'great_circle' AS method,
    round(quantile(0.50)(
        greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat)
    ), 2) AS p50_meters
FROM   geo_analytics.trips
UNION ALL
SELECT
    'geo_distance_wgs84' AS method,
    round(quantile(0.50)(
        geoDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat)
    ), 2) AS p50_meters
FROM   geo_analytics.trips
ORDER  BY method;

-- Row-level difference (in meters) for a sample of trips
-- 행 단위 차이 (미터) — 일부 트립 샘플
SELECT
    round(greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat), 2) AS gc_m,
    round(geoDistance       (pickup_lon, pickup_lat, dropoff_lon, dropoff_lat), 2) AS wgs84_m,
    round(geoDistance       (pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) -
          greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat), 2) AS diff_m
FROM   geo_analytics.trips
LIMIT  5;

-- ============================================================================
-- 5.3 Fare-per-Meter Analysis (Detect Anomalies)
-- 5.3 미터당 요금 분석 (이상값 탐지)
-- ============================================================================

-- Trips with an unusually high $/km might be surge-priced or short detours.
-- Trips with an unusually low $/km might be data errors or refunds.
-- $/km가 비정상적으로 높은 트립은 서지 가격 또는 단거리 우회 가능성,
-- 낮은 트립은 데이터 오류 또는 환불 가능성
WITH
    (SELECT quantile(0.05)(usd_per_km) FROM (
        SELECT fare_amount / (greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) / 1000) AS usd_per_km
        FROM geo_analytics.trips
        WHERE greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) > 500
    )) AS p5,
    (SELECT quantile(0.95)(usd_per_km) FROM (
        SELECT fare_amount / (greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) / 1000) AS usd_per_km
        FROM geo_analytics.trips
        WHERE greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat) > 500
    )) AS p95
SELECT
    round(p5, 2)  AS usd_per_km_p5,
    round(p95, 2) AS usd_per_km_p95;

-- ============================================================================
-- 5.4 Hex-Step Distance vs Meter Distance
-- 5.4 hex 단계 거리 vs 미터 거리
-- ============================================================================

-- For long trips, the hex-step count grows linearly with meters.
-- 장거리 트립일수록 hex 단계 수는 미터 거리에 비례해 증가
SELECT
    h3Distance(pickup_h3_r8, dropoff_h3_r8) AS hex_steps,
    count()                                  AS trips,
    round(avg(greatCircleDistance(
        pickup_lon, pickup_lat, dropoff_lon, dropoff_lat
    )), 0)                                   AS avg_meters,
    round(avg(fare_amount), 2)               AS avg_fare
FROM   geo_analytics.trips
GROUP  BY hex_steps
ORDER  BY hex_steps
LIMIT  20;

-- ============================================================================
-- 5.5 Manhattan-Distance Approximation via H3 Edge Length
-- 5.5 H3 엣지 길이로 한 도시-블록 거리 근사
-- ============================================================================

-- For a given resolution, each hex step is approximately h3EdgeLengthM(res) meters.
-- Comparing hex_steps * edge_length to the great-circle distance shows how
-- much actual NYC trips deviate from the straight line.
-- 해상도별 hex 한 칸 = 약 h3EdgeLengthM(res) 미터.
-- hex_steps * edge_length 와 대권 거리를 비교하면 실제 트립이 직선 거리에서
-- 얼마나 벗어나는지를 볼 수 있음
SELECT
    h3Distance(pickup_h3_r8, dropoff_h3_r8) AS hex_steps,
    h3Distance(pickup_h3_r8, dropoff_h3_r8) * h3EdgeLengthM(8) AS approx_m_by_hex,
    round(avg(greatCircleDistance(
        pickup_lon, pickup_lat, dropoff_lon, dropoff_lat
    )), 0) AS true_great_circle_m,
    count() AS trips
FROM   geo_analytics.trips
WHERE  h3Distance(pickup_h3_r8, dropoff_h3_r8) IN (5, 10, 20, 50, 100)
GROUP  BY hex_steps
ORDER  BY hex_steps;

-- ============================================================================
-- 5.6 Round-Trip Detection (pickup == dropoff hex)
-- 5.6 왕복 운행 탐지 (픽업/드롭오프 hex 동일)
-- ============================================================================

-- Trips that started and ended in the same res-10 hex (~66m edge) — likely
-- circular routes, app cancellations, or very short hops.
-- 같은 r10 hex (~66m 엣지) 에서 시작/종료한 트립 — 우회/취소/매우 짧은 이동 가능성
SELECT
    count()                  AS very_short_trips,
    round(avg(fare_amount), 2) AS avg_fare,
    round(avg(greatCircleDistance(
        pickup_lon, pickup_lat, dropoff_lon, dropoff_lat
    )), 0)                   AS avg_meters
FROM   geo_analytics.trips
WHERE  pickup_h3_r10 = geoToH3(dropoff_lon, dropoff_lat, 10);

SELECT 'Step 5 complete. Next: 06-spatial-search.sql' AS done;
