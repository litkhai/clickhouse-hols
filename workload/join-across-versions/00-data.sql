-- Deterministic data for the join-across-versions lab: numbers() plus cityHash64, no rand().
-- Setup only (no probes). Every later file reads these tables.

DROP DATABASE IF EXISTS join_lab;

CREATE DATABASE join_lab;

-- facts: 5M rows. Sorted by customer_id so the runtime-filter probes have a primary key to prune on.
CREATE TABLE join_lab.facts
(
    id          UInt64,
    customer_id UInt32,
    amount      UInt32,
    ts          DateTime
)
ENGINE = MergeTree
ORDER BY (customer_id, id);

INSERT INTO join_lab.facts
SELECT
    number,
    cityHash64(number, 1) % 500000,
    cityHash64(number, 2) % 10000,
    toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 3) % 2592000)
FROM numbers(5000000);

-- customers: 500k rows with a wide String column (about 200 bytes).
CREATE TABLE join_lab.customers
(
    id           UInt32,
    region       UInt8,
    credit_limit UInt32,
    comment      String
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO join_lab.customers
SELECT
    number,
    cityHash64(number, 4) % 20,
    cityHash64(number, 5) % 10000,
    concat('customer-', toString(number), '-', repeat(hex(cityHash64(number, 6)), 12))
FROM numbers(500000);

-- regions: 20 rows.
CREATE TABLE join_lab.regions
(
    id   UInt8,
    name String
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO join_lab.regions
SELECT number, concat('region-', toString(number)) FROM numbers(20);

-- bands: 100 amount ranges [lo, hi) covering 0..9999.
CREATE TABLE join_lab.bands
(
    lo UInt32,
    hi UInt32
)
ENGINE = MergeTree
ORDER BY lo;

INSERT INTO join_lab.bands
SELECT number * 100, (number + 1) * 100 FROM numbers(100);

-- prices: 2000 customers x 10 price points, one per day, for ASOF.
CREATE TABLE join_lab.prices
(
    customer_id UInt32,
    ts          DateTime,
    price       UInt32
)
ENGINE = MergeTree
ORDER BY (customer_id, ts);

INSERT INTO join_lab.prices
SELECT
    number % 2000,
    toDateTime('2026-01-01 00:00:00') + intDiv(number, 2000) * 86400,
    cityHash64(number, 7) % 1000
FROM numbers(20000);

-- contacts: 1M rows with a wide note and only 100k distinct customer_id, so joining it on
-- customer_id is many-to-many.
CREATE TABLE join_lab.contacts
(
    customer_id UInt32,
    note        String
)
ENGINE = MergeTree
ORDER BY customer_id;

INSERT INTO join_lab.contacts
SELECT
    cityHash64(number, 8) % 100000,
    concat('note-', toString(number), '-', repeat(hex(cityHash64(number, 9)), 12))
FROM numbers(1000000);

-- The big tables: ten times the rows of facts / customers / contacts. Used by 06-memory-cap.sql,
-- 10-scale.sql and errors/. Same column shapes, deterministic.
-- Every column is pinned to CODEC(LZ4): from 26.9 a merged part of 100 MiB or more defaults to ZSTD(3)
-- (ClickHouse#108786) while older builds use LZ4, which would make 10-scale timings compare codecs as
-- well as builds. Builds before 26.9 store LZ4 either way; the 10-codec probe records what was read.

CREATE TABLE join_lab.facts_big
(
    id          UInt64 CODEC(LZ4),
    customer_id UInt32 CODEC(LZ4),
    amount      UInt32 CODEC(LZ4),
    ts          DateTime CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY (customer_id, id);

INSERT INTO join_lab.facts_big
SELECT
    number,
    cityHash64(number, 1) % 5000000,
    cityHash64(number, 2) % 10000,
    toDateTime('2026-01-01 00:00:00') + (cityHash64(number, 3) % 2592000)
FROM numbers(50000000);

CREATE TABLE join_lab.customers_big
(
    id           UInt32 CODEC(LZ4),
    region       UInt8 CODEC(LZ4),
    credit_limit UInt32 CODEC(LZ4),
    comment      String CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY id;

INSERT INTO join_lab.customers_big
SELECT
    number,
    cityHash64(number, 4) % 20,
    cityHash64(number, 5) % 10000,
    concat('customer-', toString(number), '-', repeat(hex(cityHash64(number, 6)), 12))
FROM numbers(5000000);

CREATE TABLE join_lab.contacts_big
(
    customer_id UInt32 CODEC(LZ4),
    note        String CODEC(LZ4)
)
ENGINE = MergeTree
ORDER BY customer_id;

INSERT INTO join_lab.contacts_big
SELECT
    cityHash64(number, 8) % 1000000,
    concat('note-', toString(number), '-', repeat(hex(cityHash64(number, 9)), 12))
FROM numbers(5000000);
