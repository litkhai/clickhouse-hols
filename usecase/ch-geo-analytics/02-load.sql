-- ============================================================================
-- ch-geo-analytics Step 2: Load 5,000,000 Synthetic Trips
-- ch-geo-analytics 2단계: 500만 건의 합성 운행 데이터 적재
-- ============================================================================
-- Distribution strategy:
--   - Each trip picks a "pickup hotspot" via weighted sampling
--     (a precomputed 100-bucket lookup table maps a uniform random index to
--     a hotspot, with frequencies proportional to hotspots.weight).
--   - pickup_(lon,lat) is then jittered ~ Normal(σ ≈ 800 m) around the
--     chosen hotspot center, producing a realistic clustered distribution.
--   - dropoff_(lon,lat) samples a hotspot independently.
--   - pickup_ts spreads uniformly across the last 30 days.
--   - Surge multiplier inflates fares during rush hours (08-10, 17-20).
-- 분포 전략:
--   - 100칸짜리 누적 분포 lookup 테이블로 가중치에 비례한 핫스팟 선택
--   - 선택된 핫스팟 중심으로부터 σ ≈ 800m의 정규분포 jitter 적용
--   - 드롭오프도 독립적으로 동일한 방식으로 샘플링
--   - pickup_ts 는 최근 30일에 균등 분포
--   - 러시아워(08-10, 17-20)는 surge 배수가 1.5~2.0
-- ============================================================================

TRUNCATE TABLE geo_analytics.trips;

-- Pre-materialize weighted arrays so the inner SELECT runs once, not per row.
-- 가중치 lookup 테이블을 미리 만들어 행마다 재계산하지 않게 함.
INSERT INTO geo_analytics.trips
    (trip_id, user_id, pickup_ts, dropoff_ts,
     pickup_lon, pickup_lat, dropoff_lon, dropoff_lat,
     surge_multiplier, fare_amount, payment_method, vehicle_type)
WITH
    -- Hotspot coordinate arrays in hotspot_id order
    -- hotspot_id 순서대로 좌표 배열을 만들어 둠
    (SELECT groupArray(lon)    FROM (SELECT lon    FROM geo_analytics.hotspots ORDER BY hotspot_id)) AS hs_lons,
    (SELECT groupArray(lat)    FROM (SELECT lat    FROM geo_analytics.hotspots ORDER BY hotspot_id)) AS hs_lats,
    (SELECT groupArray(weight) FROM (SELECT weight FROM geo_analytics.hotspots ORDER BY hotspot_id)) AS hs_weights,

    -- Build a 100-element bucket array. bucket[i] = hotspot index whose
    -- cumulative weight contains i. Each row then does O(1) array lookup.
    -- 100칸 버킷 배열을 만들고, 각 행은 O(1) 룩업으로 핫스팟을 선택.
    arrayMap(
        i -> arrayFirstIndex(
                 cum -> cum >= (i + 1) / 100.0,
                 arrayCumSum(arrayMap(w -> w / arraySum(hs_weights), hs_weights))
             ),
        range(100)
    ) AS bucket_lookup
SELECT
    number + 1                                                 AS trip_id,
    (cityHash64(number) % 100000) + 1                          AS user_id,

    -- Pickup timestamp uniformly across May 2026 (30 days)
    -- 픽업 시각은 2026년 5월의 30일 동안 균등 분포
    addSeconds(
        toDateTime('2026-05-01 00:00:00'),
        toInt32(cityHash64(number, 'pickup_ts') % toUInt64(30 * 86400))
    )                                                          AS pickup_ts,

    addSeconds(pickup_ts,
               toInt32(180 + (cityHash64(number, 'duration') % 1800)))
                                                               AS dropoff_ts,

    -- pickup hotspot index from bucket_lookup, then add Normal jitter
    -- 픽업 핫스팟 인덱스를 lookup에서 가져온 뒤 정규분포 jitter 추가
    arrayElement(hs_lons,
        arrayElement(bucket_lookup,
            1 + (cityHash64(number, 'p_choose') % 100)))
        + (randNormal(0, 0.008)::Float64)                      AS pickup_lon,
    arrayElement(hs_lats,
        arrayElement(bucket_lookup,
            1 + (cityHash64(number, 'p_choose') % 100)))
        + (randNormal(0, 0.006)::Float64)                      AS pickup_lat,

    -- dropoff hotspot independently
    -- 드롭오프 핫스팟도 독립적으로 샘플링
    arrayElement(hs_lons,
        arrayElement(bucket_lookup,
            1 + (cityHash64(number, 'd_choose') % 100)))
        + (randNormal(0, 0.010)::Float64)                      AS dropoff_lon,
    arrayElement(hs_lats,
        arrayElement(bucket_lookup,
            1 + (cityHash64(number, 'd_choose') % 100)))
        + (randNormal(0, 0.008)::Float64)                      AS dropoff_lat,

    -- Surge: 1.0 most of the time, 1.5 morning rush, 2.0 evening rush
    -- 서지: 평상시 1.0, 아침 러시 1.5, 저녁 러시 2.0
    multiIf(
        toHour(pickup_ts) BETWEEN 8  AND 10, toDecimal32(1.5, 2),
        toHour(pickup_ts) BETWEEN 17 AND 20, toDecimal32(2.0, 2),
        toDecimal32(1.0, 2)
    )                                                          AS surge_multiplier,

    -- Fare = base + (great-circle meters * per-meter rate) * surge
    -- 요금 = 기본요금 + (대권 거리 미터 * 미터당 요금) * 서지
    round(
        (3.50 + 0.00075 *
            greatCircleDistance(pickup_lon, pickup_lat, dropoff_lon, dropoff_lat)
        ) * surge_multiplier,
        2
    )::Decimal(8, 2)                                           AS fare_amount,

    arrayElement(['card', 'cash', 'wallet'],
                  1 + (cityHash64(number, 'pay') % 3))         AS payment_method,
    arrayElement(['standard', 'xl', 'black', 'pool'],
                  1 + (cityHash64(number, 'veh') % 4))         AS vehicle_type
FROM   numbers(5000000)
SETTINGS max_insert_threads = 4, max_block_size = 100000;

-- ============================================================================
-- Confirm load
-- 적재 확인
-- ============================================================================

SELECT 'Loaded trips:' AS label, count() AS rows FROM geo_analytics.trips;

SELECT 'Date range:' AS label,
       toString(min(pickup_ts)) AS first_pickup,
       toString(max(pickup_ts)) AS last_pickup
FROM   geo_analytics.trips;

SELECT 'Hex coverage:' AS label,
       uniqExact(pickup_h3_r6)  AS unique_r6_hexes,
       uniqExact(pickup_h3_r8)  AS unique_r8_hexes,
       uniqExact(pickup_h3_r10) AS unique_r10_hexes
FROM   geo_analytics.trips;

SELECT 'Fare distribution (USD):' AS label,
       round(min(fare_amount), 2)             AS min_fare,
       round(quantile(0.50)(fare_amount), 2)  AS p50_fare,
       round(quantile(0.95)(fare_amount), 2)  AS p95_fare,
       round(max(fare_amount), 2)             AS max_fare
FROM   geo_analytics.trips;

SELECT 'Top vehicle types:' AS label,
       vehicle_type,
       count() AS trips
FROM   geo_analytics.trips
GROUP  BY vehicle_type
ORDER  BY trips DESC;
