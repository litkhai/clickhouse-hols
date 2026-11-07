-- 06 - the same designs at 10M orders and 6.2M change rows: what each costs to write and to read.
-- Source merges are stopped during the load so every build starts the reads from the same parts;
-- then merges are started, the source is OPTIMIZEd and the reads are repeated on one part.
-- settings: optimize_move_to_prewhere_if_final, max_threads, max_final_threads

DROP DATABASE IF EXISTS rmt_mv;
CREATE DATABASE rmt_mv;

CREATE TABLE rmt_mv.orders
(
    order_id   UInt64,
    day        Date,
    status     LowCardinality(String),
    amount     UInt64,
    ver        UInt64,
    is_deleted UInt8
)
ENGINE = ReplacingMergeTree(ver, is_deleted)
ORDER BY order_id;

CREATE TABLE rmt_mv.daily_naive (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_naive_mv TO rmt_mv.daily_naive AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day;

CREATE TABLE rmt_mv.order_state
(
    order_id   UInt64,
    day        AggregateFunction(argMax, Date, UInt64),
    amount     AggregateFunction(argMax, UInt64, UInt64),
    is_deleted AggregateFunction(argMax, UInt8, UInt64)
)
ENGINE = AggregatingMergeTree ORDER BY order_id;

CREATE MATERIALIZED VIEW rmt_mv.order_state_mv TO rmt_mv.order_state AS
SELECT order_id, argMaxState(day, ver) AS day, argMaxState(amount, ver) AS amount, argMaxState(is_deleted, ver) AS is_deleted
FROM rmt_mv.orders GROUP BY order_id;

CREATE TABLE rmt_mv.daily_rmv_t (day Date, orders UInt64, amount UInt64)
ENGINE = MergeTree ORDER BY day;

CREATE TABLE rmt_mv.daily_stage (day Date, orders UInt64, amount UInt64)
ENGINE = MergeTree PARTITION BY day ORDER BY day;

SYSTEM STOP MERGES rmt_mv.orders;

-- 10M orders over 30 days, version 1, about ten 1M-row parts
INSERT INTO rmt_mv.orders
SELECT number, toDate('2026-10-01') + number % 30, ['paid', 'pending', 'refunded'][number % 3 + 1], 1000 + number % 9000, 1, 0
FROM numbers(10000000)
SETTINGS max_insert_block_size = 1048576, min_insert_block_size_rows = 1048576, min_insert_block_size_bytes = 0;

-- v2: 2M orders change amount
INSERT INTO rmt_mv.orders
SELECT number * 5, toDate('2026-10-01') + (number * 5) % 30, ['paid', 'pending', 'refunded'][(number * 5) % 3 + 1], 1000 + (number * 5) % 9000 + 1, 2, 0
FROM numbers(2000000);

-- v3: 2M other orders change status and move to the next day
INSERT INTO rmt_mv.orders
SELECT number * 5 + 1, toDate('2026-10-01') + ((number * 5 + 1) % 30 + 1) % 30, 'paid', 1000 + (number * 5 + 1) % 9000, 3, 0
FROM numbers(2000000);

-- v4: 1M orders (a subset of v2's) change amount again
INSERT INTO rmt_mv.orders
SELECT number * 10, toDate('2026-10-01') + (number * 10) % 30, ['paid', 'pending', 'refunded'][(number * 10) % 3 + 1], 1000 + (number * 10) % 9000 + 2, 4, 0
FROM numbers(1000000);

-- late: v3 rows for the same 1M orders arrive after v4
INSERT INTO rmt_mv.orders
SELECT number * 10, toDate('2026-10-01') + (number * 10) % 30, ['paid', 'pending', 'refunded'][(number * 10) % 3 + 1], 1000 + (number * 10) % 9000 + 7, 3, 0
FROM numbers(1000000);

-- v5: 200k orders deleted
INSERT INTO rmt_mv.orders
SELECT number * 50 + 3, toDate('2026-10-01') + (number * 50 + 3) % 30, ['paid', 'pending', 'refunded'][(number * 50 + 3) % 3 + 1], 1000 + (number * 50 + 3) % 9000, 5, 1
FROM numbers(200000);

-- probe: 06-parts-before value
SELECT count() AS parts, sum(rows) AS rows FROM system.parts WHERE database = 'rmt_mv' AND table = 'orders' AND active;

-- every design's grand total; truth = FINAL
-- probe: 06-totals show
SELECT 'truth (FINAL)' AS design, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL
UNION ALL
SELECT 'N naive MV', sum(orders), sum(amount) FROM rmt_mv.daily_naive
UNION ALL
SELECT 'A per-key state', count(), sum(amount) FROM (SELECT order_id, argMaxMerge(amount) AS amount, argMaxMerge(is_deleted) AS d FROM rmt_mv.order_state GROUP BY order_id) WHERE d = 0
UNION ALL
SELECT 'E argMax on source', count(), sum(amount) FROM (SELECT order_id, argMax(amount, ver) AS amount, argMax(is_deleted, ver) AS d FROM rmt_mv.orders GROUP BY order_id) WHERE d = 0
UNION ALL
SELECT 'plain read, no FINAL', count(), sum(amount) FROM rmt_mv.orders WHERE is_deleted = 0;

-- per-day report, timed (3 runs each)
-- probe: 06-read-naive repeat=3
SELECT day, sum(orders), sum(amount) FROM rmt_mv.daily_naive GROUP BY day ORDER BY day FORMAT Null;

-- probe: 06-read-final repeat=3
SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL GROUP BY day ORDER BY day FORMAT Null;

-- probe: 06-read-order-state repeat=3
SELECT day, count(), sum(amount)
FROM (SELECT order_id, argMaxMerge(day) AS day, argMaxMerge(amount) AS amount, argMaxMerge(is_deleted) AS d FROM rmt_mv.order_state GROUP BY order_id)
WHERE d = 0 GROUP BY day ORDER BY day FORMAT Null;

-- probe: 06-read-argmax-source repeat=3
SELECT day, count(), sum(amount)
FROM (SELECT order_id, argMax(day, ver) AS day, argMax(amount, ver) AS amount, argMax(is_deleted, ver) AS d FROM rmt_mv.orders GROUP BY order_id)
WHERE d = 0 GROUP BY day ORDER BY day FORMAT Null;

-- C: what one full refresh of the refreshable MV does
-- probe: 06-rmv-full-refresh
INSERT INTO rmt_mv.daily_rmv_t SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL GROUP BY day;

-- D: rebuild of one day (the filter is on a non-key column, so FINAL still reads every key)
-- probe: 06-rebuild-one-day
INSERT INTO rmt_mv.daily_stage SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL WHERE day = '2026-10-15' GROUP BY day;

-- probe: 06-storage show
SELECT table, sum(rows) AS rows, count() AS parts, formatReadableSize(sum(data_compressed_bytes)) AS compressed
FROM system.parts WHERE database = 'rmt_mv' AND active AND table IN ('orders', 'daily_naive', 'order_state')
GROUP BY table ORDER BY table;

-- what one extra MV costs at insert: the same 2M-row batch into three fresh sources
CREATE TABLE rmt_mv.w_nomv AS rmt_mv.orders;
CREATE TABLE rmt_mv.w_naive AS rmt_mv.orders;
CREATE TABLE rmt_mv.w_perkey AS rmt_mv.orders;
CREATE TABLE rmt_mv.w_naive_t AS rmt_mv.daily_naive;
CREATE TABLE rmt_mv.w_perkey_t AS rmt_mv.order_state;

CREATE MATERIALIZED VIEW rmt_mv.w_naive_mv TO rmt_mv.w_naive_t AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.w_naive WHERE is_deleted = 0 GROUP BY day;

CREATE MATERIALIZED VIEW rmt_mv.w_perkey_mv TO rmt_mv.w_perkey_t AS
SELECT order_id, argMaxState(day, ver) AS day, argMaxState(amount, ver) AS amount, argMaxState(is_deleted, ver) AS is_deleted
FROM rmt_mv.w_perkey GROUP BY order_id;

-- probe: 06-insert-nomv
INSERT INTO rmt_mv.w_nomv SELECT number * 5, toDate('2026-10-01') + (number * 5) % 30, 'paid', 1000 + number % 9000, 2, 0 FROM numbers(2000000);

-- probe: 06-insert-naive-mv
INSERT INTO rmt_mv.w_naive SELECT number * 5, toDate('2026-10-01') + (number * 5) % 30, 'paid', 1000 + number % 9000, 2, 0 FROM numbers(2000000);

-- probe: 06-insert-perkey-mv
INSERT INTO rmt_mv.w_perkey SELECT number * 5, toDate('2026-10-01') + (number * 5) % 30, 'paid', 1000 + number % 9000, 2, 0 FROM numbers(2000000);

-- F: let the source merge into one part
SYSTEM START MERGES rmt_mv.orders;

-- probe: 06-optimize-final
OPTIMIZE TABLE rmt_mv.orders FINAL;

-- probe: 06-parts-after value
SELECT count() AS parts, sum(rows) AS rows FROM system.parts WHERE database = 'rmt_mv' AND table = 'orders' AND active;

-- probe: 06-read-final-1part repeat=3
SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL GROUP BY day ORDER BY day FORMAT Null;

-- probe: 06-read-plain-1part repeat=3
SELECT day, count(), sum(amount) FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day ORDER BY day FORMAT Null;

-- probe: 06-totals-after-optimize show
SELECT 'truth (FINAL)' AS design, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL
UNION ALL
SELECT 'plain read, no FINAL', count(), sum(amount) FROM rmt_mv.orders WHERE is_deleted = 0
UNION ALL
SELECT 'N naive MV', sum(orders), sum(amount) FROM rmt_mv.daily_naive;
