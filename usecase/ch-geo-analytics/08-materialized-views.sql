-- ============================================================================
-- ch-geo-analytics Step 8: Real-Time Demand Aggregation via Materialized Views
-- ch-geo-analytics 8단계: Materialized View로 실시간 수요 집계
-- ============================================================================
-- Pre-aggregating trips by (hex, hour) in a Materialized View turns the
-- "top hexes right now" query from a full table scan into a tiny lookup.
-- (hex, hour) 단위로 미리 집계해두면 "지금 가장 바쁜 hex"를 풀스캔 없이
-- 작은 룩업으로 처리 가능.
-- ============================================================================

-- ============================================================================
-- 8.1 Hourly Demand by H3 r8 — Target Table
-- 8.1 시간 × hex 단위 수요 집계 - 타겟 테이블
-- ============================================================================

DROP TABLE IF EXISTS geo_analytics.demand_by_hex_hour;
CREATE TABLE geo_analytics.demand_by_hex_hour
(
    hour_bucket  DateTime,
    hex_r8       UInt64,
    pickups      AggregateFunction(count),
    revenue      AggregateFunction(sum,   Decimal(8, 2)),
    avg_fare     AggregateFunction(avg,   Decimal(8, 2)),
    unique_users AggregateFunction(uniq,  UInt32)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour_bucket)
ORDER BY (hour_bucket, hex_r8);

-- ============================================================================
-- 8.2 Materialized View — Continuously Roll Up New Trips
-- 8.2 Materialized View - 새 트립이 들어올 때마다 자동 집계
-- ============================================================================

DROP VIEW IF EXISTS geo_analytics.demand_by_hex_hour_mv;
CREATE MATERIALIZED VIEW geo_analytics.demand_by_hex_hour_mv
TO geo_analytics.demand_by_hex_hour
AS
SELECT
    toStartOfHour(pickup_ts) AS hour_bucket,
    pickup_h3_r8             AS hex_r8,
    countState()             AS pickups,
    sumState(fare_amount)    AS revenue,
    avgState(fare_amount)    AS avg_fare,
    uniqState(user_id)       AS unique_users
FROM   geo_analytics.trips
GROUP  BY hour_bucket, hex_r8;

-- ============================================================================
-- 8.3 Backfill From Existing Data
-- 8.3 기존 데이터에서 백필
-- ============================================================================

-- The MV only catches NEW inserts. Backfill from existing trips with one shot.
-- MV는 새로 들어오는 데이터만 잡으므로, 기존 데이터는 한 번 백필이 필요.
INSERT INTO geo_analytics.demand_by_hex_hour
SELECT
    toStartOfHour(pickup_ts) AS hour_bucket,
    pickup_h3_r8             AS hex_r8,
    countState()             AS pickups,
    sumState(fare_amount)    AS revenue,
    avgState(fare_amount)    AS avg_fare,
    uniqState(user_id)       AS unique_users
FROM   geo_analytics.trips
GROUP  BY hour_bucket, hex_r8;

SELECT 'Pre-aggregated rows:' AS label, count() AS rows
FROM   geo_analytics.demand_by_hex_hour;

-- ============================================================================
-- 8.4 Querying the Aggregate (Use *Merge functions)
-- 8.4 Aggregate 컬럼은 *Merge 함수로 읽음
-- ============================================================================

-- Read pre-computed aggregates with the *Merge sibling of *State.
-- *State로 저장된 값은 같은 이름의 *Merge 함수로 읽어옴
SELECT
    h3ToString(hex_r8)            AS hex,
    countMerge(pickups)           AS pickups,
    round(sumMerge(revenue), 2)   AS revenue,
    round(avgMerge(avg_fare), 2)  AS avg_fare,
    uniqMerge(unique_users)       AS unique_users
FROM   geo_analytics.demand_by_hex_hour
GROUP  BY hex_r8
ORDER  BY pickups DESC
LIMIT  10;

-- ============================================================================
-- 8.5 Performance Comparison: Aggregate Table vs Raw trips
-- 8.5 성능 비교: 집계 테이블 vs 원본 trips
-- ============================================================================

-- Same answer from both sources — but the aggregate table reads ~5000 rows
-- instead of 5,000,000.
-- 동일한 결과를 양쪽에서 계산. 집계 테이블은 ~5천 행만 읽고, 원본은 5백만 행을 읽음.
SELECT * FROM (
    SELECT 'from_aggregate'                            AS source,
           round(sumMerge(revenue) / countMerge(pickups), 2) AS avg_fare_overall,
           countMerge(pickups)                         AS total_pickups
    FROM   geo_analytics.demand_by_hex_hour
    UNION ALL
    SELECT 'from_raw_trips'                            AS source,
           round(avg(fare_amount), 2),
           count()
    FROM   geo_analytics.trips
)
ORDER BY source;

-- ============================================================================
-- 8.6 Surge Detection — Hex × Hour Heat Map
-- 8.6 서지 감지 - hex × 시간 히트맵
-- ============================================================================

-- Pull the busiest 5 (hour, hex) combinations.
-- 가장 바쁜 (시간, hex) 5개 조합
SELECT
    hour_bucket,
    h3ToString(hex_r8) AS hex,
    countMerge(pickups) AS pickups,
    round(avgMerge(avg_fare), 2) AS avg_fare
FROM   geo_analytics.demand_by_hex_hour
GROUP  BY hour_bucket, hex_r8
ORDER  BY pickups DESC
LIMIT  5;

-- ============================================================================
-- 8.7 Live-Insert Test — MV Picks Up New Trip
-- 8.7 라이브 INSERT 테스트 - MV가 새 트립을 자동 집계하는지 확인
-- ============================================================================

-- A targeted INSERT of 100 brand-new trips in a brand-new hour
-- 새로운 시간대에 100건의 트립을 INSERT
INSERT INTO geo_analytics.trips
    (trip_id, user_id, pickup_ts, dropoff_ts,
     pickup_lon, pickup_lat, dropoff_lon, dropoff_lat,
     surge_multiplier, fare_amount, payment_method, vehicle_type)
SELECT
    9_000_000_000 + number               AS trip_id,
    99999                                AS user_id,
    toDateTime('2026-06-15 10:00:00') + INTERVAL number * 6 SECOND AS pickup_ts,
    pickup_ts + INTERVAL 600 SECOND      AS dropoff_ts,
    -73.9857 + randNormal(0, 0.001),
    40.7580  + randNormal(0, 0.001),
    -73.9772 + randNormal(0, 0.001),
    40.7527  + randNormal(0, 0.001),
    toDecimal32(1.0, 2),
    toDecimal32(15.00, 2),
    'card',
    'standard'
FROM numbers(100);

-- The aggregate table now contains a new row for hour=2026-06-15 10:00:00
-- 새 시간 행이 집계 테이블에 자동으로 생김
SELECT
    hour_bucket,
    h3ToString(hex_r8) AS hex,
    countMerge(pickups) AS pickups,
    round(avgMerge(avg_fare), 2) AS avg_fare
FROM   geo_analytics.demand_by_hex_hour
WHERE  hour_bucket = '2026-06-15 10:00:00'
GROUP  BY hour_bucket, hex_r8;

SELECT 'Step 8 complete. Lab finished. To clean up: source 99-cleanup.sql' AS done;
