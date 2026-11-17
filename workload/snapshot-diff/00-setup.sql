-- 00-setup.sql: database, a generator for hourly full snapshots, and the tables every later file uses.
--
-- The source re-delivers a FULL snapshot every hour into a plain MergeTree (for example through the
-- ClickHouse Kafka Connect Sink). Each row: record_key, 25 Nullable(String) business fields,
-- event_timestamp (changes on every delivery) and ingestion_timestamp (set when the row is written).

CREATE DATABASE IF NOT EXISTS snapdiff;

-- gen(n, v, sid): one full snapshot of n records.
--   v = 0  the base snapshot: keys 0 .. n-1
--   v = 1  the next snapshot: keys with n % 1000 < 3 are gone (deleted, 0.3 %),
--          keys n .. n + n/200 - 1 are added (new, 0.5 %),
--          f03 changes where n % 100 = 7 (1 %), and f06 goes from NULL to '' where n % 100000 = 11.
-- f06, f12, f18, f22 and f25 are NULL for about 10 % of the keys; event_timestamp moves on every snapshot.
CREATE OR REPLACE VIEW snapdiff.gen AS
SELECT
    {sid:DateTime} AS snapshot_id,
    concat('K', leftPad(toString(n), 10, '0')) AS record_key,
    CAST(concat('C', toString(cityHash64(n, 1) % 40)) AS Nullable(String)) AS f01,
    CAST(concat('C', toString(cityHash64(n, 2) % 40)) AS Nullable(String)) AS f02,
    CAST(if({v:UInt8} = 1 AND n % 100 = 7, concat(concat('C', toString(cityHash64(n, 3) % 40)), '_x'), concat('C', toString(cityHash64(n, 3) % 40))) AS Nullable(String)) AS f03,
    CAST(concat('C', toString(cityHash64(n, 4) % 40)) AS Nullable(String)) AS f04,
    CAST(concat('C', toString(cityHash64(n, 5) % 40)) AS Nullable(String)) AS f05,
    CAST(multiIf(n % 100000 = 11, if({v:UInt8} = 1, '', NULL), cityHash64(n, 6, 'null') % 10 = 0, NULL, concat('C', toString(cityHash64(n, 6) % 40))) AS Nullable(String)) AS f06,
    CAST(concat('C', toString(cityHash64(n, 7) % 40)) AS Nullable(String)) AS f07,
    CAST(concat('C', toString(cityHash64(n, 8) % 40)) AS Nullable(String)) AS f08,
    CAST(concat('C', toString(cityHash64(n, 9) % 40)) AS Nullable(String)) AS f09,
    CAST(concat('C', toString(cityHash64(n, 10) % 40)) AS Nullable(String)) AS f10,
    CAST(substring(hex(cityHash64(n, 11)), 1, 12) AS Nullable(String)) AS f11,
    CAST(if(cityHash64(n, 12, 'null') % 10 = 0, NULL, substring(hex(cityHash64(n, 12)), 1, 12)) AS Nullable(String)) AS f12,
    CAST(substring(hex(cityHash64(n, 13)), 1, 12) AS Nullable(String)) AS f13,
    CAST(substring(hex(cityHash64(n, 14)), 1, 12) AS Nullable(String)) AS f14,
    CAST(substring(hex(cityHash64(n, 15)), 1, 12) AS Nullable(String)) AS f15,
    CAST(substring(hex(cityHash64(n, 16)), 1, 12) AS Nullable(String)) AS f16,
    CAST(substring(hex(cityHash64(n, 17)), 1, 12) AS Nullable(String)) AS f17,
    CAST(if(cityHash64(n, 18, 'null') % 10 = 0, NULL, substring(hex(cityHash64(n, 18)), 1, 12)) AS Nullable(String)) AS f18,
    CAST(substring(hex(cityHash64(n, 19)), 1, 12) AS Nullable(String)) AS f19,
    CAST(substring(hex(cityHash64(n, 20)), 1, 12) AS Nullable(String)) AS f20,
    CAST(concat(hex(cityHash64(n, 21)), hex(cityHash64(n, 21, 'b'))) AS Nullable(String)) AS f21,
    CAST(if(cityHash64(n, 22, 'null') % 10 = 0, NULL, concat(hex(cityHash64(n, 22)), hex(cityHash64(n, 22, 'b')))) AS Nullable(String)) AS f22,
    CAST(concat(hex(cityHash64(n, 23)), hex(cityHash64(n, 23, 'b'))) AS Nullable(String)) AS f23,
    CAST(concat(hex(cityHash64(n, 24)), hex(cityHash64(n, 24, 'b'))) AS Nullable(String)) AS f24,
    CAST(if(cityHash64(n, 25, 'null') % 10 = 0, NULL, concat(hex(cityHash64(n, 25)), hex(cityHash64(n, 25, 'b')))) AS Nullable(String)) AS f25,
    toDateTime64({sid:DateTime}, 3) + toIntervalMillisecond(n % 600000) AS event_timestamp
FROM (SELECT number AS n FROM numbers({n:UInt64} + if({v:UInt8} = 1, intDiv({n:UInt64}, 200), 0)))
WHERE NOT ({v:UInt8} = 1 AND n < {n:UInt64} AND n % 1000 < 3);

-- The landing table. snapshot_id comes from the producer (the hour the snapshot was taken), not from ClickHouse.
-- row_hash covers the 25 business fields only (see 02-row-hash.sql), computed once at insert.
CREATE TABLE IF NOT EXISTS snapdiff.raw
(
    snapshot_id DateTime,
    record_key String,
    f01 Nullable(String),
    f02 Nullable(String),
    f03 Nullable(String),
    f04 Nullable(String),
    f05 Nullable(String),
    f06 Nullable(String),
    f07 Nullable(String),
    f08 Nullable(String),
    f09 Nullable(String),
    f10 Nullable(String),
    f11 Nullable(String),
    f12 Nullable(String),
    f13 Nullable(String),
    f14 Nullable(String),
    f15 Nullable(String),
    f16 Nullable(String),
    f17 Nullable(String),
    f18 Nullable(String),
    f19 Nullable(String),
    f20 Nullable(String),
    f21 Nullable(String),
    f22 Nullable(String),
    f23 Nullable(String),
    f24 Nullable(String),
    f25 Nullable(String),
    event_timestamp DateTime64(3),
    ingestion_timestamp DateTime64(3) DEFAULT now64(3),
    row_hash UInt64 MATERIALIZED cityHash64(tuple(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25))
)
ENGINE = MergeTree
PARTITION BY snapshot_id
ORDER BY (snapshot_id, record_key);

-- One row per snapshot, written by the producer after its last record (a control message on its own topic,
-- or an end-of-snapshot record routed to this table): how many distinct records the snapshot holds.
CREATE TABLE IF NOT EXISTS snapdiff.manifest
(
    snapshot_id DateTime,
    expected_rows UInt64,
    closed_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY snapshot_id;

-- What downstream consumers read: one row per new, changed or deleted record, and one 'end' row per
-- snapshot that has been compared (record_key = '').
CREATE TABLE IF NOT EXISTS snapdiff.changes
(
    snapshot_id DateTime,
    prev_snapshot_id DateTime,
    change_type Enum8('new' = 1, 'changed' = 2, 'deleted' = 3, 'end' = 9),
    record_key String,
    f01 Nullable(String),
    f02 Nullable(String),
    f03 Nullable(String),
    f04 Nullable(String),
    f05 Nullable(String),
    f06 Nullable(String),
    f07 Nullable(String),
    f08 Nullable(String),
    f09 Nullable(String),
    f10 Nullable(String),
    f11 Nullable(String),
    f12 Nullable(String),
    f13 Nullable(String),
    f14 Nullable(String),
    f15 Nullable(String),
    f16 Nullable(String),
    f17 Nullable(String),
    f18 Nullable(String),
    f19 Nullable(String),
    f20 Nullable(String),
    f21 Nullable(String),
    f22 Nullable(String),
    f23 Nullable(String),
    f24 Nullable(String),
    f25 Nullable(String),
    detected_at DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toDate(snapshot_id)
ORDER BY (snapshot_id, change_type, record_key)
TTL snapshot_id + INTERVAL 7 DAY;
