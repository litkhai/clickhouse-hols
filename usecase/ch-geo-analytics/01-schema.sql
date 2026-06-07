-- ============================================================================
-- ch-geo-analytics Step 1: Schema (Trips, Service Zones, City Hotspots)
-- ch-geo-analytics 1단계: 스키마 (운행 데이터, 서비스 존, 도시 핫스팟)
-- ============================================================================
-- Scenario: A ride-hailing platform analyzing NYC trip data with H3 hexagonal
--           indexing for demand heatmaps, surge detection, and zone analytics.
-- 시나리오: H3 육각 인덱싱으로 NYC 운행 데이터를 분석하는 라이드 헤일링 플랫폼
--           수요 히트맵, 서지 감지, 존 분석 등을 다룸
-- ============================================================================

CREATE DATABASE IF NOT EXISTS geo_analytics;

-- ============================================================================
-- 1.1 Trips Table (with MATERIALIZED H3 columns at 3 resolutions)
-- 1.1 운행 테이블 (3가지 해상도의 H3 컬럼을 MATERIALIZED 로 저장)
-- ============================================================================
-- H3 resolution reference (average hex edge length):
--   res 6  ~ 3.2 km   (city districts)
--   res 7  ~ 1.2 km   (neighborhoods)
--   res 8  ~ 460 m    (street blocks)       <- primary working resolution
--   res 9  ~ 175 m    (block corners)
--   res 10 ~ 66 m     (storefront level)
-- 운행 테이블에는 픽업/드롭오프 위치를 raw lat/lon으로 저장하고,
-- H3 인덱스를 res 6 / 8 / 10 세 가지 해상도로 자동 계산해 저장합니다.
-- ============================================================================

DROP TABLE IF EXISTS geo_analytics.trips;
CREATE TABLE geo_analytics.trips
(
    trip_id              UInt64,
    user_id              UInt32,
    pickup_ts            DateTime,
    dropoff_ts           DateTime,
    pickup_lon           Float64,
    pickup_lat           Float64,
    dropoff_lon          Float64,
    dropoff_lat          Float64,
    fare_amount          Decimal(8, 2),
    surge_multiplier     Decimal(4, 2),
    payment_method       LowCardinality(String),
    vehicle_type         LowCardinality(String),

    -- H3 indexes auto-computed at INSERT time
    -- H3 인덱스를 INSERT 시점에 자동 계산
    pickup_h3_r6         UInt64 MATERIALIZED geoToH3(pickup_lon,  pickup_lat,  6),
    pickup_h3_r8         UInt64 MATERIALIZED geoToH3(pickup_lon,  pickup_lat,  8),
    pickup_h3_r10        UInt64 MATERIALIZED geoToH3(pickup_lon,  pickup_lat, 10),
    dropoff_h3_r8        UInt64 MATERIALIZED geoToH3(dropoff_lon, dropoff_lat, 8),

    -- Skip index on the working-resolution H3 column for fast hex filters
    -- 자주 사용하는 해상도 컬럼에 skip 인덱스를 걸어 hex 필터 가속
    INDEX idx_pickup_h3_r8 pickup_h3_r8 TYPE minmax GRANULARITY 4
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(pickup_ts)
ORDER BY  (pickup_h3_r8, pickup_ts, trip_id)
SETTINGS  index_granularity = 8192;

-- ============================================================================
-- 1.2 Service Zones (Polygons for geofencing / surge zones)
-- 1.2 서비스 존 (지오펜싱 / 서지 존을 위한 폴리곤)
-- ============================================================================
-- A polygon is an Array((lon, lat)) of vertices, suitable for pointInPolygon().
-- 폴리곤은 (경도, 위도) 튜플의 배열이며 pointInPolygon()에 바로 사용 가능.
-- ============================================================================

DROP TABLE IF EXISTS geo_analytics.service_zones;
CREATE TABLE geo_analytics.service_zones
(
    zone_id    UInt16,
    zone_name  LowCardinality(String),
    borough    LowCardinality(String),
    -- WGS84 polygon, vertices ordered counter-clockwise
    polygon    Array(Tuple(lon Float64, lat Float64))
)
ENGINE = MergeTree()
ORDER BY zone_id;

-- A small set of representative NYC service polygons.
-- 대표적인 NYC 서비스 존 폴리곤 몇 개를 적재.
INSERT INTO geo_analytics.service_zones VALUES
    (1, 'Midtown Manhattan',  'Manhattan', [(-74.0090, 40.7480), (-73.9700, 40.7480), (-73.9700, 40.7820), (-74.0090, 40.7820), (-74.0090, 40.7480)]),
    (2, 'Downtown Manhattan', 'Manhattan', [(-74.0190, 40.7000), (-73.9700, 40.7000), (-73.9700, 40.7480), (-74.0190, 40.7480), (-74.0190, 40.7000)]),
    (3, 'Upper Manhattan',    'Manhattan', [(-74.0200, 40.7820), (-73.9300, 40.7820), (-73.9300, 40.8500), (-74.0200, 40.8500), (-74.0200, 40.7820)]),
    (4, 'Williamsburg',       'Brooklyn',  [(-73.9700, 40.7000), (-73.9300, 40.7000), (-73.9300, 40.7250), (-73.9700, 40.7250), (-73.9700, 40.7000)]),
    (5, 'JFK Airport Zone',   'Queens',    [(-73.8200, 40.6300), (-73.7600, 40.6300), (-73.7600, 40.6700), (-73.8200, 40.6700), (-73.8200, 40.6300)]),
    (6, 'LGA Airport Zone',   'Queens',    [(-73.8900, 40.7650), (-73.8500, 40.7650), (-73.8500, 40.7900), (-73.8900, 40.7900), (-73.8900, 40.7650)]),
    (7, 'Long Island City',   'Queens',    [(-73.9550, 40.7400), (-73.9300, 40.7400), (-73.9300, 40.7650), (-73.9550, 40.7650), (-73.9550, 40.7400)]);

-- ============================================================================
-- 1.3 City Hotspots (Named POIs used to bias synthetic data generation)
-- 1.3 도시 핫스팟 (합성 데이터 분포를 편향시키기 위한 명소 좌표)
-- ============================================================================

DROP TABLE IF EXISTS geo_analytics.hotspots;
CREATE TABLE geo_analytics.hotspots
(
    hotspot_id    UInt16,
    name          LowCardinality(String),
    borough       LowCardinality(String),
    lon           Float64,
    lat           Float64,
    weight        Float32   -- relative pickup demand weight / 상대적 픽업 수요 가중치
)
ENGINE = MergeTree()
ORDER BY hotspot_id;

INSERT INTO geo_analytics.hotspots VALUES
    (1,  'Times Square',         'Manhattan', -73.9857, 40.7580, 10.0),
    (2,  'Grand Central',        'Manhattan', -73.9772, 40.7527,  9.0),
    (3,  'Penn Station',         'Manhattan', -73.9933, 40.7506,  9.0),
    (4,  'Wall Street',          'Manhattan', -74.0090, 40.7060,  7.0),
    (5,  'Empire State Bldg',    'Manhattan', -73.9857, 40.7484,  6.0),
    (6,  'Union Square',         'Manhattan', -73.9911, 40.7359,  6.0),
    (7,  'Brooklyn Bridge',      'Manhattan', -73.9969, 40.7061,  4.0),
    (8,  'Williamsburg Bridge',  'Brooklyn',  -73.9716, 40.7137,  4.0),
    (9,  'Barclays Center',      'Brooklyn',  -73.9756, 40.6826,  5.0),
    (10, 'Long Island City',     'Queens',    -73.9485, 40.7461,  4.0),
    (11, 'JFK Airport',          'Queens',    -73.7781, 40.6413,  8.0),
    (12, 'LaGuardia Airport',    'Queens',    -73.8740, 40.7769,  7.0),
    (13, 'Central Park South',   'Manhattan', -73.9742, 40.7644,  6.0),
    (14, 'Harlem',               'Manhattan', -73.9442, 40.8116,  3.0),
    (15, 'Coney Island',         'Brooklyn',  -73.9784, 40.5755,  2.0);

SELECT 'Schema created. Tables:' AS message;
SELECT name, engine
FROM   system.tables
WHERE  database = 'geo_analytics'
ORDER  BY name;
