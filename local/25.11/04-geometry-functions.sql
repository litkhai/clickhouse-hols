-- ClickHouse 25.11 Feature: Geometry Functions (WKT Support)
-- Purpose: Test WKT (Well-Known Text) reading functions for spatial data
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- ClickHouse 25.11 provides readWKT* functions for parsing WKT format spatial data
-- Functions: readWKTPoint, readWKTPolygon, readWKTLineString, readWKTMultiPolygon, etc.

-- Drop table if exists
DROP TABLE IF EXISTS spatial_data;

-- Create a table with Tuple types for storing geometric data
CREATE TABLE spatial_data
(
    id UInt32,
    location_name String,
    point_geom Tuple(Float64, Float64),  -- (longitude, latitude)
    description String
)
ENGINE = MergeTree()
ORDER BY id;

-- Insert sample spatial data using readWKTPoint function
INSERT INTO spatial_data SELECT
    id,
    name,
    readWKTPoint(wkt_point) AS point_geom,
    description
FROM (
    SELECT 1 AS id, 'Central Park' AS name, 'POINT(-73.9654 40.7829)' AS wkt_point, 'Famous park in Manhattan' AS description
    UNION ALL
    SELECT 2, 'Times Square', 'POINT(-73.9851 40.7580)', 'Major commercial intersection'
    UNION ALL
    SELECT 3, 'Brooklyn Bridge', 'POINT(-73.9969 40.7061)', 'Historic bridge connecting Manhattan and Brooklyn'
    UNION ALL
    SELECT 4, 'Statue of Liberty', 'POINT(-74.0445 40.6892)', 'Iconic monument and UNESCO World Heritage Site'
    UNION ALL
    SELECT 5, 'Empire State Building', 'POINT(-73.9857 40.7484)', 'Art Deco skyscraper'
);

-- Query 1: View all spatial data
SELECT '=== All Spatial Data ===' AS title;
SELECT
    id,
    location_name,
    point_geom,
    description
FROM spatial_data
ORDER BY id;

-- Query 2: Extract coordinates from tuples
SELECT '=== Extracted Coordinates ===' AS title;
SELECT
    id,
    location_name,
    point_geom.1 AS longitude,
    point_geom.2 AS latitude,
    description
FROM spatial_data
ORDER BY id;

-- Query 3: Calculate distances using geoDistance
SELECT '=== Distance from Times Square ===' AS title;
SELECT
    s1.location_name AS from_location,
    s2.location_name AS to_location,
    round(geoDistance(s1.point_geom.1, s1.point_geom.2, s2.point_geom.1, s2.point_geom.2), 2) AS distance_meters
FROM spatial_data s1
CROSS JOIN spatial_data s2
WHERE s1.id = 2 AND s2.id != 2  -- From Times Square to other locations
ORDER BY distance_meters;

-- Real-world use case: Store and query polygon data
DROP TABLE IF EXISTS city_zones;

CREATE TABLE city_zones
(
    zone_id UInt64,
    city String,
    zone_name String,
    zone_boundary Array(Tuple(Float64, Float64)),  -- Polygon represented as array of points
    category String
)
ENGINE = MergeTree()
ORDER BY (city, zone_id);

-- Insert zone data using readWKTPolygon
INSERT INTO city_zones SELECT
    zone_id,
    city,
    zone_name,
    readWKTPolygon(wkt_polygon) AS zone_boundary,
    category
FROM (
    SELECT 1 AS zone_id, 'New York' AS city, 'Manhattan' AS zone_name,
           'POLYGON((-74.0 40.7,-73.9 40.7,-73.9 40.8,-74.0 40.8,-74.0 40.7))' AS wkt_polygon,
           'District' AS category
    UNION ALL
    SELECT 2, 'New York', 'Brooklyn',
           'POLYGON((-74.0 40.6,-73.8 40.6,-73.8 40.7,-74.0 40.7,-74.0 40.6))',
           'District'
    UNION ALL
    SELECT 3, 'San Francisco', 'Downtown',
           'POLYGON((-122.5 37.7,-122.3 37.7,-122.3 37.8,-122.5 37.8,-122.5 37.7))',
           'Business'
);

-- Query 4: View zone data
SELECT '=== City Zones ===' AS title;
SELECT
    zone_id,
    city,
    zone_name,
    length(zone_boundary) AS num_points,
    category
FROM city_zones
ORDER BY city, zone_id;

-- Query 5: City zones summary
SELECT '=== Zones by City ===' AS title;
SELECT
    city,
    count() AS zone_count,
    groupArray(zone_name) AS zones
FROM city_zones
GROUP BY city
ORDER BY zone_count DESC;

-- Use case: POI (Points of Interest) with distance calculations
DROP TABLE IF EXISTS points_of_interest;

CREATE TABLE points_of_interest
(
    poi_id UInt64,
    poi_name String,
    location Tuple(Float64, Float64),
    poi_type String,
    rating Float32
)
ENGINE = MergeTree()
ORDER BY poi_id;

-- Insert POI data
INSERT INTO points_of_interest VALUES
    (1, 'Restaurant A', (-73.9654, 40.7829), 'restaurant', 4.5),
    (2, 'Museum B', (-73.9851, 40.7580), 'museum', 4.8),
    (3, 'Hotel C', (-73.9969, 40.7061), 'hotel', 4.2),
    (4, 'Park D', (-74.0445, 40.6892), 'park', 4.7),
    (5, 'Shop E', (-73.9857, 40.7484), 'shop', 4.0);

-- Query 6: Find nearby POIs (within 5000 meters of a reference point)
SELECT '=== Nearby POIs (within 5km of Times Square) ===' AS title;
WITH reference AS (
    SELECT -73.9851 AS ref_lon, 40.7580 AS ref_lat
)
SELECT
    poi_name,
    poi_type,
    rating,
    round(geoDistance(location.1, location.2, ref_lon, ref_lat), 2) AS distance_meters
FROM points_of_interest, reference
WHERE geoDistance(location.1, location.2, ref_lon, ref_lat) < 5000
ORDER BY distance_meters;

-- Query 7: POIs grouped by type with average rating
SELECT '=== POIs by Type ===' AS title;
SELECT
    poi_type,
    count() AS count,
    round(avg(rating), 2) AS avg_rating,
    groupArray(poi_name) AS pois
FROM points_of_interest
GROUP BY poi_type
ORDER BY avg_rating DESC;

-- Advanced: geohash encoding for spatial indexing
SELECT '=== Geohash Encoding ===' AS title;
SELECT
    poi_name,
    location,
    geohashEncode(location.1, location.2, 8) AS geohash_8chars,
    geohashEncode(location.1, location.2, 6) AS geohash_6chars
FROM points_of_interest
ORDER BY poi_id
LIMIT 5;

-- Benefits of WKT Functions
SELECT '=== WKT Functions Benefits ===' AS info;
SELECT
    'readWKTPoint/Polygon for parsing WKT format data' AS benefit_1,
    'Native support for spatial data operations' AS benefit_2,
    'Integration with geoDistance for proximity queries' AS benefit_3,
    'geohash support for spatial indexing' AS benefit_4,
    'Tuple types for efficient coordinate storage' AS benefit_5;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'GIS and mapping applications' AS use_case_1,
    'Location-based services and POI search' AS use_case_2,
    'Spatial data analysis and proximity queries' AS use_case_3,
    'Urban planning and zone management' AS use_case_4,
    'Logistics and route optimization' AS use_case_5,
    'Real estate and property management' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE points_of_interest;
-- DROP TABLE city_zones;
-- DROP TABLE spatial_data;

SELECT '✅ Geometry Functions Test Complete!' AS status;
