-- 04 — A small workload of our own, tagged with log_comment (writes: database systables_lab)

CREATE DATABASE IF NOT EXISTS systables_lab;

-- Where this run starts: later steps read only log rows from here on, so a re-run
-- on the same day does not mix with the previous one
CREATE TABLE IF NOT EXISTS systables_lab.run (started DateTime) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO systables_lab.run SELECT now() - 1;

-- In Cloud, ENGINE = MergeTree becomes SharedMergeTree
CREATE TABLE IF NOT EXISTS systables_lab.events
(
    ts      DateTime,
    user_id UInt32,
    country LowCardinality(String),
    amount  Decimal(10, 2),
    payload String
)
ENGINE = MergeTree
ORDER BY (country, ts);

CREATE TABLE IF NOT EXISTS systables_lab.daily
(
    day     Date,
    country LowCardinality(String),
    orders  UInt64,
    revenue Decimal(18, 2)
)
ENGINE = SummingMergeTree
ORDER BY (day, country);

CREATE MATERIALIZED VIEW IF NOT EXISTS systables_lab.daily_mv TO systables_lab.daily AS
SELECT toDate(ts) AS day, country, count() AS orders, sum(amount) AS revenue
FROM systables_lab.events
GROUP BY day, country;

SELECT engine FROM system.tables WHERE database = 'systables_lab' AND name = 'events';

-- Five inserts of 1M rows each: five new parts, then background merges
INSERT INTO systables_lab.events
SELECT toDateTime('2026-01-01 00:00:00') + intDiv(number, 12), (number * 7919) % 100000,
       ['KR', 'JP', 'US', 'DE', 'BR', 'IN', 'SG', 'FR'][1 + number % 8], toDecimal64((number % 10000) / 100, 2),
       concat('order-', toString(number), '-', hex(sipHash64(number)))
FROM numbers(0, 1000000) SETTINGS log_comment = 'lab:insert-1';
INSERT INTO systables_lab.events
SELECT toDateTime('2026-01-01 00:00:00') + intDiv(number, 12), (number * 7919) % 100000,
       ['KR', 'JP', 'US', 'DE', 'BR', 'IN', 'SG', 'FR'][1 + number % 8], toDecimal64((number % 10000) / 100, 2),
       concat('order-', toString(number), '-', hex(sipHash64(number)))
FROM numbers(1000000, 1000000) SETTINGS log_comment = 'lab:insert-2';
INSERT INTO systables_lab.events
SELECT toDateTime('2026-01-01 00:00:00') + intDiv(number, 12), (number * 7919) % 100000,
       ['KR', 'JP', 'US', 'DE', 'BR', 'IN', 'SG', 'FR'][1 + number % 8], toDecimal64((number % 10000) / 100, 2),
       concat('order-', toString(number), '-', hex(sipHash64(number)))
FROM numbers(2000000, 1000000) SETTINGS log_comment = 'lab:insert-3';
INSERT INTO systables_lab.events
SELECT toDateTime('2026-01-01 00:00:00') + intDiv(number, 12), (number * 7919) % 100000,
       ['KR', 'JP', 'US', 'DE', 'BR', 'IN', 'SG', 'FR'][1 + number % 8], toDecimal64((number % 10000) / 100, 2),
       concat('order-', toString(number), '-', hex(sipHash64(number)))
FROM numbers(3000000, 1000000) SETTINGS log_comment = 'lab:insert-4';
INSERT INTO systables_lab.events
SELECT toDateTime('2026-01-01 00:00:00') + intDiv(number, 12), (number * 7919) % 100000,
       ['KR', 'JP', 'US', 'DE', 'BR', 'IN', 'SG', 'FR'][1 + number % 8], toDecimal64((number % 10000) / 100, 2),
       concat('order-', toString(number), '-', hex(sipHash64(number)))
FROM numbers(4000000, 1000000) SETTINGS log_comment = 'lab:insert-5';

-- Four reads: a full aggregate, the same with the filesystem cache off,
-- a primary-key range and a filter the key cannot help with
SELECT country, count() AS orders, sum(amount) AS revenue
FROM systables_lab.events GROUP BY country ORDER BY orders DESC
SETTINGS log_comment = 'lab:q-scan';

SELECT country, count() AS orders, sum(amount) AS revenue
FROM systables_lab.events GROUP BY country ORDER BY orders DESC
SETTINGS log_comment = 'lab:q-scan-nocache', enable_filesystem_cache = 0;

SELECT count() FROM systables_lab.events
WHERE country = 'KR' AND ts >= '2026-01-02 00:00:00' AND ts < '2026-01-02 01:00:00'
SETTINGS log_comment = 'lab:q-pk';

SELECT count() FROM systables_lab.events
WHERE user_id = 4242
SETTINGS log_comment = 'lab:q-no-pk';

-- A mutation
ALTER TABLE systables_lab.events UPDATE payload = '' WHERE country = 'JP'
SETTINGS log_comment = 'lab:mutation', mutations_sync = 2;
