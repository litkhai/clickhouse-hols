-- ClickHouse 25.5 Feature: Geo Types in Parquet
-- Purpose: Test enhanced Parquet reader for geographic data types
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-05

SELECT '=== Geo Types in Parquet Feature ===' AS title;
SELECT
    'ClickHouse 25.5 properly handles WKB-encoded geometry in Parquet' AS feature,
    'Auto-infers Point, LineString, MultiLineString, Polygon, MultiPolygon' AS types,
    'Previously displayed as binary, now parses as geo types' AS improvement,
    'Enables analysis of GeoParquet datasets like Overture Maps' AS benefit;

-- =====================================
-- Point Geometry
-- =====================================

SELECT '=== Point Geometry ===' AS title;

DROP TABLE IF EXISTS geo_points;

CREATE TABLE geo_points
(
    point_id UInt32,
    location_name String,
    point Point,  -- Point type: (longitude, latitude)
    category String,
    properties String
)
ENGINE = MergeTree()
ORDER BY point_id;

-- Insert sample point data
-- Format: (longitude, latitude) - note the order!
INSERT INTO geo_points VALUES
    (1, 'New York City', (40.7128, -74.0060), 'City', '{"population": 8336817}'),
    (2, 'Los Angeles', (34.0522, -118.2437), 'City', '{"population": 3979576}'),
    (3, 'Chicago', (41.8781, -87.6298), 'City', '{"population": 2693976}'),
    (4, 'Golden Gate Bridge', (37.8199, -122.4783), 'Landmark', '{"opened": 1937}'),
    (5, 'Statue of Liberty', (40.6892, -74.0445), 'Monument', '{"height_m": 93}'),
    (6, 'Eiffel Tower', (48.8584, 2.2945), 'Landmark', '{"height_m": 330}'),
    (7, 'Tokyo Tower', (35.6586, 139.7454), 'Landmark', '{"height_m": 333}'),
    (8, 'Big Ben', (51.5007, -0.1246), 'Landmark', '{"height_m": 96}'),
    (9, 'Sydney Opera House', (-33.8568, 151.2153), 'Landmark', '{"opened": 1973}'),
    (10, 'Burj Khalifa', (25.1972, 55.2744), 'Building', '{"height_m": 828}');

-- Query 1: Basic point queries
SELECT '--- Point Coordinates ---' AS query;
SELECT
    location_name,
    point,
    tupleElement(point, 1) AS latitude,
    tupleElement(point, 2) AS longitude,
    category
FROM geo_points
LIMIT 5;

-- Query 2: Calculate distances between points (Great Circle Distance)
SELECT '--- Distance Calculations (NYC to other cities) ---' AS query;
SELECT
    p1.location_name AS from_location,
    p2.location_name AS to_location,
    greatCircleDistance(
        tupleElement(p1.point, 2), tupleElement(p1.point, 1),
        tupleElement(p2.point, 2), tupleElement(p2.point, 1)
    ) AS distance_meters,
    round(greatCircleDistance(
        tupleElement(p1.point, 2), tupleElement(p1.point, 1),
        tupleElement(p2.point, 2), tupleElement(p2.point, 1)
    ) / 1000, 2) AS distance_km
FROM geo_points p1
CROSS JOIN geo_points p2
WHERE p1.point_id = 1 AND p2.point_id != 1
ORDER BY distance_meters;

-- =====================================
-- LineString Geometry
-- =====================================

SELECT '=== LineString Geometry ===' AS title;

DROP TABLE IF EXISTS geo_routes;

CREATE TABLE geo_routes
(
    route_id UInt32,
    route_name String,
    path Array(Point),  -- LineString as array of points
    route_type String,
    distance_km Float64
)
ENGINE = MergeTree()
ORDER BY route_id;

-- Insert sample route data
INSERT INTO geo_routes VALUES
    (1, 'NYC to Boston', [(40.7128, -74.0060), (41.8240, -71.4128), (42.3601, -71.0589)], 'Highway', 346),
    (2, 'SF to LA', [(37.7749, -122.4194), (36.7783, -119.4179), (34.0522, -118.2437)], 'Highway', 617),
    (3, 'London to Paris', [(51.5074, -0.1278), (50.8503, 4.3517), (48.8566, 2.3522)], 'Rail', 492),
    (4, 'Tokyo Circle Line', [(35.6762, 139.7653), (35.6812, 139.7671), (35.6895, 139.6917), (35.6762, 139.7653)], 'Rail', 34.5),
    (5, 'Coast Highway 1', [(37.8199, -122.4783), (36.9741, -122.0308), (36.6002, -121.8947), (35.3733, -120.8493)], 'Scenic', 187);

-- Query: Route analysis
SELECT '--- Route Information ---' AS query;
SELECT
    route_name,
    route_type,
    length(path) AS waypoints,
    distance_km,
    path[1] AS start_point,
    path[length(path)] AS end_point
FROM geo_routes;

-- =====================================
-- Polygon Geometry
-- =====================================

SELECT '=== Polygon Geometry ===' AS title;

DROP TABLE IF EXISTS geo_regions;

CREATE TABLE geo_regions
(
    region_id UInt32,
    region_name String,
    boundary Array(Point),  -- Polygon boundary
    area_km2 Float64,
    population UInt32
)
ENGINE = MergeTree()
ORDER BY region_id;

-- Insert sample polygon data (simplified boundaries)
INSERT INTO geo_regions VALUES
    (1, 'Central Park NYC', [(40.7682, -73.9816), (40.7682, -73.9497), (40.7642, -73.9497), (40.7642, -73.9816), (40.7682, -73.9816)], 3.41, 0),
    (2, 'Golden Gate Park SF', [(37.7694, -122.5107), (37.7694, -122.4548), (37.7654, -122.4548), (37.7654, -122.5107), (37.7694, -122.5107)], 4.1, 0),
    (3, 'Hyde Park London', [(51.5074, -0.1657), (51.5074, -0.1588), (51.5020, -0.1588), (51.5020, -0.1657), (51.5074, -0.1657)], 1.4, 0);

-- Query: Region analysis
SELECT '--- Region Information ---' AS query;
SELECT
    region_name,
    area_km2,
    length(boundary) AS boundary_points,
    boundary[1] AS northwest_corner,
    population
FROM geo_regions;

-- =====================================
-- Real-world GeoParquet Use Cases
-- =====================================

SELECT '=== Real-World GeoParquet Use Cases ===' AS title;

-- Store locations with spatial data
DROP TABLE IF EXISTS retail_stores;

CREATE TABLE retail_stores
(
    store_id UInt32,
    store_name String,
    location Point,
    service_area Array(Point),  -- Delivery polygon
    city String,
    state String,
    revenue_last_month Decimal(12, 2),
    customer_count UInt32
)
ENGINE = MergeTree()
ORDER BY (state, city, store_id);

INSERT INTO retail_stores VALUES
    (101, 'Downtown Store', (40.7589, -73.9851), [(40.7689, -73.9951), (40.7689, -73.9751), (40.7489, -73.9751), (40.7489, -73.9951), (40.7689, -73.9951)], 'New York', 'NY', 125000.50, 3200),
    (102, 'Midtown Store', (40.7549, -73.9840), [(40.7649, -73.9940), (40.7649, -73.9740), (40.7449, -73.9740), (40.7449, -73.9940), (40.7649, -73.9940)], 'New York', 'NY', 145000.75, 3800),
    (103, 'Brooklyn Store', (40.6782, -73.9442), [(40.6882, -73.9542), (40.6882, -73.9342), (40.6682, -73.9342), (40.6682, -73.9542), (40.6882, -73.9542)], 'Brooklyn', 'NY', 98000.25, 2500),
    (104, 'SF Mission Store', (37.7599, -122.4148), [(37.7699, -122.4248), (37.7699, -122.4048), (37.7499, -122.4048), (37.7499, -122.4248), (37.7699, -122.4248)], 'San Francisco', 'CA', 135000.00, 3400),
    (105, 'LA Venice Store', (33.9850, -118.4695), [(33.9950, -118.4795), (33.9950, -118.4595), (33.9750, -118.4595), (33.9750, -118.4795), (33.9950, -118.4795)], 'Los Angeles', 'CA', 112000.50, 2900);

-- Query 1: Store performance by location
SELECT '--- Store Performance Analysis ---' AS query;
SELECT
    state,
    count(*) AS store_count,
    sum(revenue_last_month) AS total_revenue,
    avg(revenue_last_month) AS avg_revenue_per_store,
    sum(customer_count) AS total_customers
FROM retail_stores
GROUP BY state
ORDER BY total_revenue DESC;

-- Query 2: Find nearby stores
SELECT '--- Stores Near Reference Point ---' AS query;
WITH reference AS (
    SELECT (40.7589, -73.9851) AS ref_point
)
SELECT
    s.store_name,
    s.city,
    s.state,
    s.location,
    round(greatCircleDistance(
        tupleElement(r.ref_point, 2), tupleElement(r.ref_point, 1),
        tupleElement(s.location, 2), tupleElement(s.location, 1)
    ) / 1000, 2) AS distance_km
FROM retail_stores s, reference r
ORDER BY distance_km
LIMIT 5;

-- Query 3: Spatial clustering analysis
SELECT '--- Store Density by City ---' AS query;
SELECT
    city,
    state,
    count(*) AS store_count,
    avg(customer_count) AS avg_customers,
    avg(revenue_last_month) AS avg_revenue
FROM retail_stores
GROUP BY city, state
ORDER BY store_count DESC, avg_revenue DESC;

-- Real-world GeoParquet datasets
SELECT '=== Popular GeoParquet Datasets ===' AS info;
SELECT
    'Overture Maps - Global mapping data' AS dataset_1,
    'OpenStreetMap exports - Geospatial features' AS dataset_2,
    'Census TIGER/Line - US geographic boundaries' AS dataset_3,
    'Natural Earth - Cultural and physical vectors' AS dataset_4,
    'GADM - Global administrative boundaries' AS dataset_5;

-- Benefits of Geo Types in Parquet
SELECT '=== Benefits ===' AS info;
SELECT
    'Native parsing of WKB-encoded geometries' AS benefit_1,
    'No manual binary conversion needed' AS benefit_2,
    'Seamless integration with GeoParquet standard' AS benefit_3,
    'Efficient spatial queries on large datasets' AS benefit_4,
    'Direct analysis of geo data lakes' AS benefit_5;

-- Use cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Retail: Store location analysis and service area optimization' AS use_case_1,
    'Logistics: Route planning and delivery zone management' AS use_case_2,
    'Real Estate: Property location analytics and market analysis' AS use_case_3,
    'Urban Planning: City infrastructure and zoning analysis' AS use_case_4,
    'Transportation: Traffic patterns and network optimization' AS use_case_5,
    'Environmental: Climate data and ecosystem monitoring' AS use_case_6;

-- Spatial query patterns
SELECT '=== Common Spatial Queries ===' AS info;
SELECT
    'Point-in-polygon: Is location within boundary?' AS query_1,
    'Distance calculations: How far between points?' AS query_2,
    'Nearest neighbor: Find closest N points' AS query_3,
    'Buffer zones: All points within X distance' AS query_4,
    'Spatial joins: Match features by location' AS query_5,
    'Clustering: Group nearby features together' AS query_6;

-- Performance tips
SELECT '=== Performance Tips ===' AS info;
SELECT
    'Partition by geographic regions for faster queries' AS tip_1,
    'Use appropriate spatial indexes when available' AS tip_2,
    'Pre-filter with bounding boxes before precise calculations' AS tip_3,
    'Consider resolution/precision for coordinates' AS tip_4,
    'Use materialized views for common spatial aggregations' AS tip_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE retail_stores;
-- DROP TABLE geo_regions;
-- DROP TABLE geo_routes;
-- DROP TABLE geo_points;

SELECT '✅ Geo Types in Parquet Test Complete!' AS status;
