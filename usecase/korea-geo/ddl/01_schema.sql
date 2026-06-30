-- ===========================================================================
-- 한국 시군구 지도 랩 — ClickHouse 스키마
-- 좌표는 반드시 WGS84(EPSG:4326, degree). 5179(미터) 넣으면 조용히 틀린 결과.
-- ===========================================================================

CREATE DATABASE IF NOT EXISTS geospatial;

-- ① Polygon Dictionary 소스 테이블 (전체 MultiPolygon)
--    구조 = [polygon][ring][point(lon,lat)]
CREATE TABLE IF NOT EXISTS geospatial.sig_polygons
(
    key  Array(Array(Array(Tuple(Float64, Float64)))),
    code String,
    name String
)
ENGINE = MergeTree ORDER BY code;

-- ② Superset deck.gl Polygon 시각화용 (외곽 ring 1개 = 1행)
--    coordinates 는 [[lon,lat],...] JSON 문자열
CREATE TABLE IF NOT EXISTS geospatial.sig_map
(
    code        String,
    name        String,
    metric      Float64,
    coordinates String
)
ENGINE = MergeTree ORDER BY code;

-- Polygon Dictionary (리버스 지오코딩: (lon,lat) → code/name)
-- 컨테이너 내부 self-reference 라 HOST=localhost, PORT=9000(native).
-- LIFETIME(0)=자동 reload 안 함 → 데이터 적재 후 SYSTEM RELOAD DICTIONARY 로 1회 로드한다.
CREATE DICTIONARY IF NOT EXISTS geospatial.sig_dict
(
    key  Array(Array(Array(Tuple(Float64, Float64)))),
    code String,
    name String
)
PRIMARY KEY key
SOURCE(CLICKHOUSE(HOST 'localhost' PORT 9000 DB 'geospatial' TABLE 'sig_polygons' USER 'default'))
LAYOUT(POLYGON(STORE_POLYGON_KEY_COLUMN 1))
LIFETIME(0);
