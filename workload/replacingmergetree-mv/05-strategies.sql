-- 05 - one small history with every hazard from 01–03, read through seven designs.
-- Hazards: an update (order 1), a late older version (order 2), a key moving to another day (order 3),
-- a delete (order 4), an untouched order (order 5).
-- Truth by day: 2026-11-01 = 3 orders / 870 (orders 1, 2, 5) · 2026-11-02 = 1 order / 300 (order 3).

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

-- N: naive per-day MV
CREATE TABLE rmt_mv.daily_naive (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_naive_mv TO rmt_mv.daily_naive AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day;

-- A: per-key state, rolled up at query time
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

-- C: refreshable MV over the source with FINAL (EMPTY: no first refresh at CREATE)
CREATE TABLE rmt_mv.daily_rmv_t (day Date, orders UInt64, amount UInt64)
ENGINE = MergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_rmv REFRESH EVERY 1 HOUR TO rmt_mv.daily_rmv_t EMPTY AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL GROUP BY day;

-- D: per-day target fed by the naive MV, partitions rebuilt from the source
CREATE TABLE rmt_mv.daily_part (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree PARTITION BY day ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_part_mv TO rmt_mv.daily_part AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day;

CREATE TABLE rmt_mv.daily_part_stage AS rmt_mv.daily_part;

-- B: writer-side retraction — the writer knows the previous row and sends (old, -1) + (new, +1)
CREATE TABLE rmt_mv.order_changes (order_id UInt64, day Date, amount UInt64, sign Int8, ver UInt64)
ENGINE = MergeTree ORDER BY (order_id, ver);

CREATE TABLE rmt_mv.daily_signed (day Date, orders Int64, amount Int64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_signed_mv TO rmt_mv.daily_signed AS
SELECT day, sum(sign) AS orders, sum(toInt64(amount) * sign) AS amount FROM rmt_mv.order_changes GROUP BY day;

-- the history, one insert per event
INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'paid', 100, 1, 0), (2, '2026-11-01', 'pending', 200, 1, 0), (3, '2026-11-01', 'paid', 300, 1, 0), (4, '2026-11-01', 'paid', 400, 1, 0), (5, '2026-11-01', 'paid', 500, 1, 0);
INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'paid', 150, 2, 0);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'paid', 220, 3, 0);
INSERT INTO rmt_mv.orders VALUES (3, '2026-11-02', 'paid', 300, 2, 0);
INSERT INTO rmt_mv.orders VALUES (4, '2026-11-01', 'paid', 400, 2, 1);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'pending', 210, 2, 0);

-- the same history as change rows; the late v2 of order 2 is dropped by the writer (it already holds v3)
INSERT INTO rmt_mv.order_changes VALUES (1, '2026-11-01', 100, 1, 1), (2, '2026-11-01', 200, 1, 1), (3, '2026-11-01', 300, 1, 1), (4, '2026-11-01', 400, 1, 1), (5, '2026-11-01', 500, 1, 1);
INSERT INTO rmt_mv.order_changes VALUES (1, '2026-11-01', 100, -1, 2), (1, '2026-11-01', 150, 1, 2);
INSERT INTO rmt_mv.order_changes VALUES (2, '2026-11-01', 200, -1, 3), (2, '2026-11-01', 220, 1, 3);
INSERT INTO rmt_mv.order_changes VALUES (3, '2026-11-01', 300, -1, 2), (3, '2026-11-02', 300, 1, 2);
INSERT INTO rmt_mv.order_changes VALUES (4, '2026-11-01', 400, -1, 2);

-- truth
-- probe: 05-truth-final show
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL GROUP BY day ORDER BY day;

-- N
-- probe: 05-N-naive show
SELECT day, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_naive GROUP BY day ORDER BY day;

-- A
-- probe: 05-A-order-state show
SELECT day, count() AS orders, sum(amount) AS amount
FROM
(
    SELECT order_id, argMaxMerge(day) AS day, argMaxMerge(amount) AS amount, argMaxMerge(is_deleted) AS is_deleted
    FROM rmt_mv.order_state GROUP BY order_id
)
WHERE is_deleted = 0
GROUP BY day ORDER BY day;

-- B
-- probe: 05-B-signed show
SELECT day, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_signed GROUP BY day HAVING orders != 0 ORDER BY day;

-- C before the refresh: whatever the last refresh wrote (here: nothing)
-- probe: 05-C-rmv-before-refresh value
SELECT count() FROM rmt_mv.daily_rmv_t;

SYSTEM REFRESH VIEW rmt_mv.daily_rmv;
SYSTEM WAIT VIEW rmt_mv.daily_rmv;

-- probe: 05-C-rmv-after-refresh show
SELECT day, orders, amount FROM rmt_mv.daily_rmv_t ORDER BY day;

-- D before the rebuild: the naive numbers
-- probe: 05-D-part-before show
SELECT day, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_part GROUP BY day ORDER BY day;

-- rebuild both touched days from the source (WHERE on a non-key column with FINAL is applied after FINAL)
INSERT INTO rmt_mv.daily_part_stage SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL WHERE day IN ('2026-11-01', '2026-11-02') GROUP BY day;
ALTER TABLE rmt_mv.daily_part REPLACE PARTITION '2026-11-01' FROM rmt_mv.daily_part_stage;
ALTER TABLE rmt_mv.daily_part REPLACE PARTITION '2026-11-02' FROM rmt_mv.daily_part_stage;
TRUNCATE TABLE rmt_mv.daily_part_stage;

-- probe: 05-D-part-after show
SELECT day, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_part GROUP BY day ORDER BY day;

-- E: no MV — argMax over the source without FINAL
-- probe: 05-E-argmax-source show
SELECT day, count() AS orders, sum(amount) AS amount
FROM
(
    SELECT order_id, argMax(day, ver) AS day, argMax(amount, ver) AS amount, argMax(is_deleted, ver) AS is_deleted
    FROM rmt_mv.orders GROUP BY order_id
)
WHERE is_deleted = 0
GROUP BY day ORDER BY day;

-- F: OPTIMIZE … FINAL, then read without FINAL — right only until the next insert
OPTIMIZE TABLE rmt_mv.orders FINAL;

-- probe: 05-F-after-optimize-plain show
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day ORDER BY day;

INSERT INTO rmt_mv.orders VALUES (5, '2026-11-01', 'paid', 550, 2, 0);

-- probe: 05-F-next-insert-plain show
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY day ORDER BY day;
