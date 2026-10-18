-- Synthetic device (UE) traces: three fictional cities, placed in open ocean so that no
-- coordinate points to a real place; two hours ending at the current minute, about 9 rows per
-- grid cell per minute on average, denser near each centre. A scaled-down volume: 180,000
-- rows a minute in all, far below a real operator's trace intake. Everything is generated
-- here; nothing comes from outside. Each row's location is assumed to come from MDT
-- (TS 37.320) location reports or a positioning result, mapped to H3.

-- ---------------------------------------------------------------- the map grid
INSERT INTO oss_lake.grid
WITH
    [(-35.0000, -125.0000), (-37.4000, -122.0000), (-36.7000, -123.5000)] AS centres,
    -- one weak-coverage spot per city, about 20 rings out from its centre
    [(-34.9665, -124.9480), (-37.4296, -122.0456), (-36.6664, -123.5414)] AS holes,
    -- the serving site: one per res-8 area downtown, one per res-7 area further out
    if(ring <= 25, h3ToParent(h3, 8), h3ToParent(h3, 7)) AS site_area
SELECT
    city,
    toUInt32(row_number() OVER (PARTITION BY city ORDER BY ring, h3) - 1) AS idx,
    ring, h3, is_hole,
    site_area AS site,
    toUInt8(h3Distance(h3ToCenterChild(site_area, 9), h3)) AS site_dist
FROM
(
    SELECT
        toUInt8(c - 1)                                                  AS city,
        arrayJoin(h3kRing(geoToH3(centres[c].1, centres[c].2, 9), 47)) AS h3,
        toUInt8(h3Distance(geoToH3(centres[c].1, centres[c].2, 9), h3)) AS ring,
        toUInt8(h3Distance(geoToH3(holes[c].1, holes[c].2, 9), h3) <= 1) AS is_hole
    FROM (SELECT arrayJoin([1, 2, 3]) AS c)
);

-- ---------------------------------------------------------------- the inventory
-- Every grid cell gets its site and a fictional district: 'Central' within 10 rings, otherwise
-- one of six 60-degree sectors around the city centre. Coverage holes are known weak spots.
INSERT INTO oss_lake.cell_inventory
WITH
    [(-35.0000, -125.0000), (-37.4000, -122.0000), (-36.7000, -123.5000)] AS centres,
    ['North-East', 'East', 'South-East', 'South-West', 'West', 'North-West'] AS sectors,
    centres[city + 1] AS c,
    h3ToGeo(h3) AS p,
    (degrees(atan2((p.2 - c.2) * cos(radians(c.1)), p.1 - c.1)) + 360) % 360 AS bearing
SELECT
    h3                                                            AS cell,
    concat(['A', 'B', 'C'][city + 1], '-', lower(hex(site)))      AS site_id,
    ['City A', 'City B', 'City C'][city + 1]                      AS region1,
    concat(['A', 'B', 'C'][city + 1], ' ',
           if(ring <= 10, 'Central', sectors[1 + toUInt8(floor(bearing / 60)) % 6])) AS region2,
    is_hole                                                       AS known_weak
FROM oss_lake.grid;

SYSTEM RELOAD DICTIONARY oss_lake.cell_dict;

-- ---------------------------------------------------------------- the devices
-- A parameterized view: `minutes` minutes of traces starting at `start`.
-- 02 uses it for the two-hour history, the demo's live feed for one more minute.
CREATE VIEW oss_lake.synth_traces AS
WITH
    180000 AS per_minute,                 -- rows per minute, all cities
    6769   AS per_city,                   -- grid cells per city
    (SELECT groupArray((h3, ring, is_hole, site, site_dist))
       FROM (SELECT h3, ring, is_hole, site, site_dist FROM oss_lake.grid ORDER BY city, idx)) AS g,
    toUnixTimestamp({start:DateTime}) AS seed,
    intDiv(number, per_minute)                      AS m,
    -- every minute one res-7 area (about 49 cells) somewhere in a city has an incident:
    -- its signal drops by 22 dB for that minute, so alerts have something to catch
    (SELECT groupArray(a) FROM (SELECT DISTINCT h3ToParent(h3, 7) AS a FROM oss_lake.grid
       WHERE ring BETWEEN 8 AND 40 ORDER BY a)) AS areas,
    areas[1 + cityHash64(intDiv(seed, 60) + m) % greatest(length(areas), 1)] AS incident_area,
    number % per_minute % 3                         AS city,
    -- pow(u, 1.8) leans towards 0 = the centre: crowded downtown, quiet edges
    toUInt32(floor(per_city * pow((cityHash64(seed, number, 1) % 1000000) / 1e6, 1.8))) AS k,
    city * per_city + k + 1                         AS gi,
    g[gi].1 AS cell, g[gi].2 AS ring, g[gi].3 AS hole, g[gi].4 AS site, g[gi].5 AS site_dist,
    -- coverage: distance to the serving site (steeper for the small downtown sites), a little
    -- extra loss further out, a fixed offset per site (terrain, antenna) and per city
    -76 + [0, -3, 2][city + 1] + (toInt32(cityHash64(site) % 13) - 6)
        - site_dist * if(ring <= 25, 5, 3.5) - ring * 0.15                  AS coverage,
    -- 80% of samples come from the cell's regulars (48 devices), the rest from passers-by
    if(cityHash64(seed, number, 2) % 100 < 80,
       gi * 64 + cityHash64(seed, number, 3) % 48,
       5000000 + cityHash64(seed, number, 3) % 3000000)                     AS subscriber,
    -- roughly normal noise, sd ~6 dB
    ((cityHash64(seed, number, 4) % 1000 + cityHash64(seed, number, 5) % 1000
      + cityHash64(seed, number, 6) % 1000) / 1000 - 1.5) * 12              AS noise,
    greatest(-140, least(-44, round(if(hole, -117, coverage) + noise
        - if(h3ToParent(cell, 7) = incident_area, 22, 0))))                  AS rsrp_v,
    greatest(-19.5, least(-3, round(2 * (-8 + (rsrp_v + 90) * 0.12 + noise * 0.1)) / 2)) AS rsrq_v,
    round(2 * ((rsrp_v + 105) * 0.5 + noise * 0.2)) / 2                      AS sinr_v
SELECT
    toDateTime64({start:DateTime}, 3) + toIntervalMillisecond(m * 60000 + cityHash64(seed, number, 7) % 60000) AS event_ts,
    if(cityHash64(seed, number, 8) % 1000 < 3, NULL, h3ToString(cell))       AS h3_res09,
    if(cityHash64(seed, number, 9) % 1000 < 3, NULL,
       base64Encode(SHA256(concat('00101', leftPad(toString(subscriber), 10, '0'))))) AS imsi,
    if(cityHash64(seed, number, 10) % 100 < 10, NULL, rsrp_v)                AS rsrp,
    rsrq_v                                                                   AS rsrq,
    sinr_v                                                                   AS sinr,
    toString(toUInt8(greatest(1, least(15, round((sinr_v + 6) / 2)))))       AS cqi,
    toUInt16(cityHash64(site) % 504)                                         AS pci,   -- fixed per serving site (LTE: 504 PCIs)
    ['probe-a', 'probe-b'][1 + cityHash64(seed, number, 12) % 2]            AS probe
FROM numbers(per_minute * {minutes:UInt32});

-- ---------------------------------------------------------------- two hours of history
-- 'Now' is pinned first; the history is the 120 minutes before it.
INSERT INTO oss_lake.params SELECT toStartOfMinute(now());

INSERT INTO oss_lake.ue_trace_raw (event_ts, h3_res09, imsi, rsrp, rsrq, sinr, cqi, pci, probe)
SELECT * FROM oss_lake.synth_traces(
    start = (SELECT max(anchor_ts) - INTERVAL 120 MINUTE FROM oss_lake.params), minutes = 120);

-- Background merges fold gold's duplicate (minute, cell) rows over time; fold them now
-- so its row count reads as minutes x cells.
OPTIMIZE TABLE oss_lake.cell_kpi_1m FINAL;
