# Geospatial Analytics with ClickHouse — H3 Indexing Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on, end-to-end laboratory for geospatial analytics on ClickHouse, centered on **H3 hexagonal indexing**. Built around a synthetic 5 million-trip NYC ride-hailing dataset, it walks you through every geo primitive ClickHouse ships with — hex indexing, distance calculations, point-in-polygon, k-ring neighbor search, polygon-to-hex coverage, side-by-side comparison with Geohash and S2, and real-time aggregation via `AggregatingMergeTree` + Materialized Views.

### 🎯 Why this lab

ClickHouse is one of the very few OLAP databases that ships H3 (Uber's hexagonal spatial index), S2 (Google's quadrilateral index), and Geohash as first-class native functions. Mobility, IoT, retail-foot-traffic, and ad-tech teams already use all three at scale. This lab shows how to combine them with `MATERIALIZED` columns and `AggregatingMergeTree` to turn raw lat/lon points into queryable geo-analytic surfaces.

### 📊 Dataset

A synthetic NYC ride-hailing platform:
- **Trips**: 5,000,000 (30 days, May 2026)
- **Hotspots**: 15 named POIs (Times Square, JFK, LGA, …) used as cluster centers for weighted sampling
- **Service zones**: 7 polygons (Midtown, Downtown, Williamsburg, JFK/LGA airports, etc.)
- Each trip stores `pickup_lon/lat`, `dropoff_lon/lat`, plus `MATERIALIZED` H3 columns at **res 6 / 8 / 10**
- Distribution is realistic: pickups cluster around hotspots with σ ≈ 800 m jitter; rush-hour surge multipliers (1.5× morning, 2.0× evening); fares scale with great-circle distance

### 📁 File Structure

```
ch-geo-analytics/
├── README.md                     # This file
├── 01-schema.sql                 # trips + service_zones + hotspots tables
├── 02-load.sql                   # 5M synthetic trips with weighted hotspot sampling
├── 03-h3-basics.sql              # H3 fundamentals: encoding, hierarchy, k-ring, distance
├── 04-demand-heatmap.sql         # Multi-resolution hex aggregation, top-N, OD flows
├── 05-distance-and-routing.sql   # greatCircle / geo / h3PointDist / h3Line / hex steps
├── 06-spatial-search.sql         # K-ring, pointInPolygon, OD matrix, hybrid pre-filter
├── 07-indexing-systems.sql       # H3 vs Geohash vs S2 side-by-side
├── 08-materialized-views.sql     # AggregatingMergeTree for real-time demand aggregates
└── 99-cleanup.sql                # Drop everything
```

### 🚀 Quick Start

```bash
cd usecase/ch-geo-analytics

# Sequential — uses the running ClickHouse from your local setup
for f in 01-schema.sql 02-load.sql 03-h3-basics.sql \
         04-demand-heatmap.sql 05-distance-and-routing.sql \
         06-spatial-search.sql 07-indexing-systems.sql \
         08-materialized-views.sql; do
    echo "▶ Running $f"
    clickhouse-client --multiquery --queries-file "$f"
done
```

Or against the bundled Docker stack (e.g. the `local/pg-clickhouse-lab` container):

```bash
for f in 01-schema.sql 02-load.sql 03-h3-basics.sql \
         04-demand-heatmap.sql 05-distance-and-routing.sql \
         06-spatial-search.sql 07-indexing-systems.sql \
         08-materialized-views.sql; do
    cat "$f" | docker exec -i pgch-clickhouse clickhouse-client --multiquery
done
```

### 📖 Lab Walkthrough

#### 01 — Schema ([01-schema.sql](01-schema.sql))

Creates the `geo_analytics` database and three tables:

```sql
CREATE TABLE geo_analytics.trips (
    trip_id        UInt64,
    pickup_lon     Float64,
    pickup_lat     Float64,
    dropoff_lon    Float64,
    dropoff_lat    Float64,
    -- ... timestamps, fare, surge, payment, vehicle_type
    pickup_h3_r6   UInt64 MATERIALIZED geoToH3(pickup_lon, pickup_lat, 6),
    pickup_h3_r8   UInt64 MATERIALIZED geoToH3(pickup_lon, pickup_lat, 8),
    pickup_h3_r10  UInt64 MATERIALIZED geoToH3(pickup_lon, pickup_lat, 10),
    dropoff_h3_r8  UInt64 MATERIALIZED geoToH3(dropoff_lon, dropoff_lat, 8),
    INDEX idx_pickup_h3_r8 pickup_h3_r8 TYPE minmax GRANULARITY 4
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(pickup_ts)
ORDER BY  (pickup_h3_r8, pickup_ts, trip_id);
```

The `MATERIALIZED` H3 columns are the foundation: each is computed once at INSERT and lives on disk, so demand-heatmap queries scan only the relevant hex columns and never re-encode raw lat/lon.

#### 02 — Synthetic data ([02-load.sql](02-load.sql))

Generates 5 M trips with weighted hotspot sampling. Implementation detail worth understanding:

```sql
-- 100-bucket lookup table: bucket[i] maps to a hotspot index by cumulative weight.
-- Each row does an O(1) array lookup instead of a per-row correlated subquery.
arrayMap(
    i -> arrayFirstIndex(
             cum -> cum >= (i + 1) / 100.0,
             arrayCumSum(arrayMap(w -> w / arraySum(hs_weights), hs_weights))
         ),
    range(100)
) AS bucket_lookup
```

Bias: 15 hotspots with weights `[10, 9, 9, 7, 6, ...]` produce realistic Manhattan-heavy distribution.

#### 03 — H3 fundamentals ([03-h3-basics.sql](03-h3-basics.sql))

| Function | Purpose |
|---|---|
| `geoToH3(lon, lat, res)` | encode point → UInt64 hex index |
| `h3ToGeo(h3)` | hex → center lat/lon |
| `h3ToString(h3)` | UInt64 → 15-char hex string (e.g. `88f05ab6adfffff`) |
| `h3EdgeLengthM(res)`, `h3HexAreaM2(res)` | reference table per resolution |
| `h3ToParent(h3, res)`, `h3ToChildren(h3, res)` | hierarchy navigation |
| `h3kRing(h3, k)` | all hexes within k rings (`= 3k² + 3k + 1` cells) |
| `h3Distance(a, b)` | hex-grid steps (integer) |
| `h3PointDistM(lat1, lon1, lat2, lon2)` | meters between hex centers |
| `h3IsValid`, `h3IsPentagon`, `h3GetBaseCell` | introspection |

> **Hierarchy quirk:** H3 hex nesting is *approximate*. The res-10 hex of a raw point does NOT always have the res-8 hex of that same point as its `h3ToParent` — they can disagree near hex boundaries. For consistent roll-ups, store only the finest resolution and derive coarser ones via `h3ToParent()`.

#### 04 — Demand heatmap ([04-demand-heatmap.sql](04-demand-heatmap.sql))

The killer pattern: aggregate millions of trips by hex.

```sql
SELECT h3ToString(pickup_h3_r8) AS hex,
       h3ToGeo(pickup_h3_r8)    AS center_lat_lon,
       count()                  AS pickups
FROM   geo_analytics.trips
GROUP  BY pickup_h3_r8
ORDER  BY pickups DESC LIMIT 10;
```

Covered:
- City-wide overview at res 6 (~3.2 km cells)
- Block-level heatmap at res 8 (~460 m cells)
- Multi-resolution roll-up via `h3ToParent` from a single stored r10 column
- Hourly rank × hex (window function)
- Pickup vs dropoff imbalance (driver supply/demand)
- `h3ToGeoBoundary` → polygon overlay for Leaflet/Mapbox/deck.gl

#### 05 — Distance & routing ([05-distance-and-routing.sql](05-distance-and-routing.sql))

Three distance flavors:
- `greatCircleDistance(lon, lat, lon, lat)` — spherical, fastest
- `geoDistance(lon, lat, lon, lat)` — WGS84 ellipsoid, more accurate
- `h3PointDistM(lat, lon, lat, lon)` — hex center to hex center (**note: lat-first**)
- `h3Distance(h3a, h3b)` — hex grid steps (integer)

Sub-queries include trip-length distribution, fare-per-km outlier detection, hex-step vs meter correlation, and round-trip (same-hex pickup/dropoff) detection.

#### 06 — Spatial search ([06-spatial-search.sql](06-spatial-search.sql))

Three patterns:
1. **K-ring filter** — `WHERE pickup_h3_r8 IN h3kRing(center, k)` for "all trips within ~k * edge meters of center"
2. **Point-in-polygon** — `pointInPolygon((lon, lat), polygon)` for arbitrary service zones, including a full Origin-Destination matrix between every pair of zones
3. **Hybrid pre-filter** — `h3PolygonToCells(polygon, res)` → `IN ()` hex pre-filter, then `pointInPolygon()` on survivors. Trades a fast hex-IN filter for a slower per-row geometry test.

> **`h3PolygonToCells` gotcha:** takes `Array(Tuple(LAT, LON))` — opposite of `geoToH3(lon, lat, res)` and `pointInPolygon((lon, lat), poly)`. If you store polygons as `(lon, lat)`, swap on the way in with `arrayMap(p -> (p.2, p.1), polygon)`.

#### 07 — H3 vs Geohash vs S2 ([07-indexing-systems.sql](07-indexing-systems.sql))

| | H3 | Geohash | S2 |
|---|---|---|---|
| Cell shape | Hexagon | Rectangle | Quadrilateral |
| Storage | `UInt64` | `String` (variable length) | `UInt64` |
| Hierarchy | 16 resolutions | Prefix nesting | 30 levels |
| Equal-area | Yes (almost) | No (varies by latitude) | Yes (within tolerance) |
| Best for | Mobility, demand heatmaps, k-ring neighbor analysis | String-prefix searches, URL params, geocoding APIs | Global services, Hilbert-curve coverage |

ClickHouse provides:
- `geohashEncode(lon, lat, precision)` / `geohashDecode(s)` / `geohashesInBox(...)`
- `geoToS2(lon, lat)` / `s2ToGeo(s2)` / `s2CapContains`, `s2CapUnion`, `s2CellsIntersect`

#### 08 — Real-time aggregation ([08-materialized-views.sql](08-materialized-views.sql))

Pre-aggregate trips by `(hour_bucket, hex_r8)` so dashboard queries scan ~72k rows instead of 5 M:

```sql
CREATE TABLE demand_by_hex_hour (
    hour_bucket  DateTime,
    hex_r8       UInt64,
    pickups      AggregateFunction(count),
    revenue      AggregateFunction(sum, Decimal(8, 2)),
    avg_fare     AggregateFunction(avg, Decimal(8, 2)),
    unique_users AggregateFunction(uniq, UInt32)
) ENGINE = AggregatingMergeTree() ORDER BY (hour_bucket, hex_r8);

CREATE MATERIALIZED VIEW demand_by_hex_hour_mv TO demand_by_hex_hour AS
SELECT toStartOfHour(pickup_ts), pickup_h3_r8,
       countState(), sumState(fare_amount),
       avgState(fare_amount), uniqState(user_id)
FROM   trips
GROUP  BY ...
```

Queries use `countMerge`, `sumMerge`, `avgMerge`, `uniqMerge` to read aggregate state. The lab also includes a live-INSERT test that proves the MV picks up new trips automatically.

### 🔑 Gotchas worth remembering

| | Note |
|---|---|
| **Coordinate order** | `geoToH3(lon, lat, res)` and `pointInPolygon((lon, lat), poly)` are **lon-first**. `h3PointDistM(lat, lon, lat, lon)` and `h3PolygonToCells([(lat, lon), …], res)` are **lat-first**. |
| **Named-tuple polygons** | `h3PolygonToCells` requires unnamed `Tuple(Float64, Float64)`. Strip column names with `arrayMap(p -> (p.1, p.2), polygon)`. |
| **H3 hierarchy is approximate** | The res-10 hex of a point may not roll up to the res-8 hex of that same point. Store the finest resolution and derive coarser ones via `h3ToParent()` for consistent results. |
| **`system.numbers` is infinite** | Use `numbers(N)` table function instead of `system.numbers LIMIT N` — `count()` on the former terminates, the latter does not. |
| **INSERT column order** | The INSERT column list and SELECT projection list must align positionally. A swap silently produces wrong values. |

### 🔍 Additional resources

- [H3 documentation](https://h3geo.org/) — Uber's H3 reference (resolution table, geometry, API)
- [ClickHouse geo functions reference](https://clickhouse.com/docs/sql-reference/functions/geo)
- [ClickHouse H3 functions reference](https://clickhouse.com/docs/sql-reference/functions/geo/h3)
- [S2 Geometry library](http://s2geometry.io/)
- [Geohash specification](https://en.wikipedia.org/wiki/Geohash)

### 📝 Verification

All scripts verified end-to-end against ClickHouse 26.5.1.882 from an empty state:

| Script | Lines of output | Errors |
|---|---|---|
| `01-schema.sql` | 4 | 0 |
| `02-load.sql` | 8 | 0 |
| `03-h3-basics.sql` | 54 | 0 |
| `04-demand-heatmap.sql` | 161 | 0 |
| `05-distance-and-routing.sql` | 39 | 0 |
| `06-spatial-search.sql` | 39 | 0 |
| `07-indexing-systems.sql` | 39 | 0 |
| `08-materialized-views.sql` | 21 | 0 |

---

**Happy Mapping! 🗺️**

For questions, see the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse에서 지리정보 분석을 위한 종단간 실습 환경입니다. 핵심은 **H3 육각 인덱싱**이며, 합성된 NYC 라이드 헤일링 트립 500만 건을 사용해 ClickHouse가 기본 제공하는 지리 함수 전반 — hex 인덱싱, 거리 계산, 점-폴리곤 포함, k-ring 이웃 검색, 폴리곤→hex 변환, Geohash/S2와의 비교, `AggregatingMergeTree` + Materialized View를 통한 실시간 집계 — 을 모두 다룹니다.

### 🎯 왜 이 랩인가

H3 (Uber 육각 인덱스), S2 (Google 사각 인덱스), Geohash를 모두 1급 함수로 내장한 OLAP DB는 ClickHouse가 유일에 가깝습니다. 모빌리티, IoT, 리테일 풋트래픽, 광고테크 팀이 이 세 가지를 대규모로 사용 중이며, 본 랩은 `MATERIALIZED` 컬럼과 `AggregatingMergeTree`를 결합해 raw lat/lon 좌표를 쿼리 가능한 지리분석 표면으로 변환하는 방법을 보여줍니다.

### 📊 데이터셋

합성 NYC 라이드 헤일링 플랫폼:
- **트립**: 5,000,000건 (2026년 5월의 30일)
- **핫스팟**: 15개의 명명된 POI (타임스퀘어, JFK, LGA, …) — 가중치 샘플링의 클러스터 중심
- **서비스 존**: 7개의 폴리곤 (미드타운, 다운타운, 윌리엄스버그, JFK/LGA 공항 등)
- 각 트립에 `pickup_lon/lat`, `dropoff_lon/lat` 와 함께 **res 6 / 8 / 10** 의 `MATERIALIZED` H3 컬럼 저장
- 현실적인 분포: 픽업이 핫스팟 주변에 σ ≈ 800m로 군집, 러시아워 서지 (아침 1.5×, 저녁 2.0×), 요금은 대권 거리에 비례

### 📁 파일 구조

```
ch-geo-analytics/
├── README.md                     # 이 문서
├── 01-schema.sql                 # trips + service_zones + hotspots 테이블
├── 02-load.sql                   # 500만 트립 합성 데이터 (가중치 샘플링)
├── 03-h3-basics.sql              # H3 기본: 인코딩, 계층, k-ring, 거리
├── 04-demand-heatmap.sql         # 다중 해상도 hex 집계, top-N, OD flow
├── 05-distance-and-routing.sql   # greatCircle / geo / h3PointDist / h3Line / hex 단계
├── 06-spatial-search.sql         # K-ring, pointInPolygon, OD 매트릭스, 하이브리드 사전 필터
├── 07-indexing-systems.sql       # H3 vs Geohash vs S2 비교
├── 08-materialized-views.sql     # AggregatingMergeTree로 실시간 수요 집계
└── 99-cleanup.sql                # 모든 객체 삭제
```

### 🚀 빠른 시작

```bash
cd usecase/ch-geo-analytics

# 순차 실행 — 로컬에서 실행 중인 ClickHouse 활용
for f in 01-schema.sql 02-load.sql 03-h3-basics.sql \
         04-demand-heatmap.sql 05-distance-and-routing.sql \
         06-spatial-search.sql 07-indexing-systems.sql \
         08-materialized-views.sql; do
    echo "▶ Running $f"
    clickhouse-client --multiquery --queries-file "$f"
done
```

도커 컨테이너 (예: `local/pg-clickhouse-lab`)에 대해 실행하려면:

```bash
for f in 01-schema.sql 02-load.sql 03-h3-basics.sql \
         04-demand-heatmap.sql 05-distance-and-routing.sql \
         06-spatial-search.sql 07-indexing-systems.sql \
         08-materialized-views.sql; do
    cat "$f" | docker exec -i pgch-clickhouse clickhouse-client --multiquery
done
```

### 📖 랩 워크스루

#### 01 — 스키마

`geo_analytics` 데이터베이스와 세 개의 테이블을 생성. `MATERIALIZED` H3 컬럼이 핵심으로, INSERT 시점에 한 번 계산되어 디스크에 저장되므로 수요 히트맵 쿼리는 raw 좌표를 재인코딩하지 않고 hex 컬럼만 스캔합니다.

#### 02 — 합성 데이터

500만 트립을 가중치 핫스팟 샘플링으로 생성. 핵심 트릭은 **100칸 룩업 테이블** — 행마다 correlated subquery를 돌리는 대신 O(1) 배열 룩업으로 핫스팟을 선택합니다.

#### 03 — H3 기본

| 함수 | 용도 |
|---|---|
| `geoToH3(lon, lat, res)` | 좌표 → UInt64 hex 인덱스 |
| `h3ToGeo(h3)` | hex → 중심 lat/lon |
| `h3ToString(h3)` | UInt64 → 15자 hex 문자열 |
| `h3EdgeLengthM(res)`, `h3HexAreaM2(res)` | 해상도별 레퍼런스 |
| `h3ToParent`, `h3ToChildren` | 계층 탐색 |
| `h3kRing(h3, k)` | k링 내부 hex (`= 3k² + 3k + 1`개) |
| `h3Distance(a, b)` | hex 단계 거리 (정수) |
| `h3PointDistM(lat1, lon1, lat2, lon2)` | hex 중심점 간 미터 거리 |
| `h3IsValid`, `h3IsPentagon`, `h3GetBaseCell` | 유효성 검사 |

> **계층 주의:** H3 hex 중첩은 *근사적*입니다. 같은 raw 좌표를 r10과 r8로 따로 인코딩하면 경계 근처에서 `h3ToParent(r10, 8) ≠ r8`이 될 수 있습니다. 일관된 롤업을 위해서는 가장 세밀한 해상도만 저장하고 `h3ToParent()`로 거친 해상도를 유도하세요.

#### 04 — 수요 히트맵

수백만 트립을 hex 단위로 집계하는 ClickHouse의 핵심 패턴. 포함:
- 도시 전체 (res 6, ~3.2 km)
- 블록 단위 (res 8, ~460 m)
- r10 컬럼에서 `h3ToParent`로 멀티 해상도 롤업
- 시간 × hex 윈도우 랭킹
- 픽업/드롭오프 불균형 (드라이버 공급/수요)
- `h3ToGeoBoundary` → Leaflet/Mapbox/deck.gl 폴리곤 오버레이

#### 05 — 거리 & 라우팅

거리 함수 세 가지:
- `greatCircleDistance(lon, lat, ...)` — 구체, 가장 빠름
- `geoDistance(lon, lat, ...)` — WGS84 타원체, 더 정확
- `h3PointDistM(lat, lon, ...)` — hex 중심 간 (**lat 먼저**)
- `h3Distance(h3a, h3b)` — hex 단계 (정수)

트립 거리 분포, $/km 이상값 탐지, hex 단계 vs 미터 상관관계, 왕복 (동일 hex 픽업/드롭오프) 탐지 포함.

#### 06 — 공간 검색

세 가지 패턴:
1. **K-ring 필터** — `WHERE pickup_h3_r8 IN h3kRing(center, k)` 로 중심 주변 트립
2. **점-폴리곤** — `pointInPolygon((lon, lat), polygon)` 으로 임의 서비스 존 + 전체 OD 매트릭스
3. **하이브리드 사전 필터** — `h3PolygonToCells(polygon, res)` → `IN ()` hex 사전 필터 → 살아남은 행에만 `pointInPolygon()` 적용

> **`h3PolygonToCells` 함정:** `Array(Tuple(위도, 경도))` 를 받음. `geoToH3(경도, 위도, ...)` 및 `pointInPolygon((경도, 위도), ...)`와 인자 순서가 정반대. 폴리곤을 (경도, 위도)로 저장했다면 `arrayMap(p -> (p.2, p.1), polygon)` 으로 swap 필수.

#### 07 — H3 vs Geohash vs S2

| | H3 | Geohash | S2 |
|---|---|---|---|
| 셀 모양 | 육각형 | 사각형 | 사각형 |
| 저장 | `UInt64` | `String` (가변) | `UInt64` |
| 계층 | 16 해상도 | 접두사 중첩 | 30 단계 |
| 동일면적 | 거의 그렇다 | 위도에 따라 변동 | 허용 오차 내 |
| 적합한 용도 | 모빌리티, 수요 히트맵, k-ring 이웃 | 문자열 접두사 검색, URL 파라미터, 지오코딩 API | 글로벌 서비스, 힐버트 커브 |

ClickHouse 제공 함수:
- `geohashEncode(lon, lat, precision)` / `geohashDecode(s)` / `geohashesInBox(...)`
- `geoToS2(lon, lat)` / `s2ToGeo(s2)` / `s2CapContains`, `s2CapUnion`, `s2CellsIntersect`

#### 08 — 실시간 집계

`(시간 버킷, hex_r8)` 단위로 사전 집계해 대시보드 쿼리가 500만 행 대신 ~72,000 행만 스캔하도록 합니다:

```sql
CREATE TABLE demand_by_hex_hour (
    hour_bucket  DateTime,
    hex_r8       UInt64,
    pickups      AggregateFunction(count),
    revenue      AggregateFunction(sum, Decimal(8, 2)),
    ...
) ENGINE = AggregatingMergeTree() ORDER BY (hour_bucket, hex_r8);

CREATE MATERIALIZED VIEW demand_by_hex_hour_mv TO demand_by_hex_hour AS
SELECT toStartOfHour(pickup_ts), pickup_h3_r8,
       countState(), sumState(fare_amount), ...
FROM trips GROUP BY ...
```

쿼리는 `countMerge`, `sumMerge`, `avgMerge`, `uniqMerge` 로 집계 상태를 읽습니다. 새 INSERT가 MV에 자동 반영되는지 확인하는 라이브 테스트도 포함.

### 🔑 기억할 함정들

| | 노트 |
|---|---|
| **좌표 순서** | `geoToH3(경도, 위도, 해상도)`와 `pointInPolygon((경도, 위도), ...)`는 **경도 먼저**. `h3PointDistM(위도, 경도, ...)`와 `h3PolygonToCells([(위도, 경도), …], 해상도)`는 **위도 먼저**. |
| **Named Tuple 폴리곤** | `h3PolygonToCells`는 unnamed `Tuple(Float64, Float64)` 만 받음. 컬럼명 제거: `arrayMap(p -> (p.1, p.2), polygon)`. |
| **H3 계층 근사성** | 한 점의 res-10 hex의 `h3ToParent(8)`이 같은 점의 res-8 hex와 다를 수 있음. 가장 세밀한 해상도만 저장하고 `h3ToParent()`로 거친 해상도 유도. |
| **`system.numbers`는 무한** | `system.numbers LIMIT N` 대신 `numbers(N)` 사용 — 전자에서 `count()`는 종료되지 않음. |
| **INSERT 컬럼 순서** | INSERT 컬럼 리스트와 SELECT 프로젝션 리스트의 위치가 일치해야 함. swap되면 조용히 잘못된 값이 들어감. |

### 🔍 추가 자료

- [H3 documentation](https://h3geo.org/) — Uber의 H3 공식 레퍼런스
- [ClickHouse geo 함수 레퍼런스](https://clickhouse.com/docs/sql-reference/functions/geo)
- [ClickHouse H3 함수 레퍼런스](https://clickhouse.com/docs/sql-reference/functions/geo/h3)
- [S2 Geometry library](http://s2geometry.io/)
- [Geohash specification](https://en.wikipedia.org/wiki/Geohash)

### 📝 검증

빈 상태에서 ClickHouse 26.5.1.882 에 대해 모든 스크립트가 end-to-end 검증됨:

| Script | 출력 라인 | 오류 |
|---|---|---|
| `01-schema.sql` | 4 | 0 |
| `02-load.sql` | 8 | 0 |
| `03-h3-basics.sql` | 54 | 0 |
| `04-demand-heatmap.sql` | 161 | 0 |
| `05-distance-and-routing.sql` | 39 | 0 |
| `06-spatial-search.sql` | 39 | 0 |
| `07-indexing-systems.sql` | 39 | 0 |
| `08-materialized-views.sql` | 21 | 0 |

---

**Happy Mapping! 🗺️**

질문이나 이슈는 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
