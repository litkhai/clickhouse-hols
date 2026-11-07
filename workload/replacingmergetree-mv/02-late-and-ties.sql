-- 02 - a late (older) version, and two rows with the same version.
-- The source keeps the highest version whatever the arrival order; the per-day MV adds the late row too.
-- A per-key target with argMaxState(…, ver) gets the late row right; ties are where it and FINAL can disagree.

DROP DATABASE IF EXISTS rmt_mv;
CREATE DATABASE rmt_mv;

CREATE TABLE rmt_mv.orders
(
    order_id UInt64,
    day      Date,
    status   LowCardinality(String),
    amount   UInt64,
    ver      UInt64
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY order_id;

CREATE TABLE rmt_mv.daily_sum (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_sum_mv TO rmt_mv.daily_sum AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders GROUP BY day;

-- strategy A: keep the MV at the source's grain (one row per order_id) and pick the latest version per key
CREATE TABLE rmt_mv.order_state
(
    order_id UInt64,
    day      AggregateFunction(argMax, Date, UInt64),
    status   AggregateFunction(argMax, LowCardinality(String), UInt64),
    amount   AggregateFunction(argMax, UInt64, UInt64),
    max_ver  SimpleAggregateFunction(max, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY order_id;

CREATE MATERIALIZED VIEW rmt_mv.order_state_mv TO rmt_mv.order_state AS
SELECT order_id,
       argMaxState(day, ver)    AS day,
       argMaxState(status, ver) AS status,
       argMaxState(amount, ver) AS amount,
       max(ver)                 AS max_ver   -- not `AS ver`: the alias would shadow ver inside argMaxState (Code 184)
FROM rmt_mv.orders
GROUP BY order_id;

-- order 10: v1 then v3 arrive in order, v2 arrives last (a retry from a lagging producer)
INSERT INTO rmt_mv.orders VALUES (10, '2026-11-01', 'paid', 100, 1);
INSERT INTO rmt_mv.orders VALUES (10, '2026-11-01', 'paid', 130, 3);
INSERT INTO rmt_mv.orders VALUES (10, '2026-11-01', 'paid', 120, 2);

-- truth: 1 order, 130
-- probe: 02-late-source-final value
SELECT count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL;

-- probe: 02-late-target-sum value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_sum;

-- probe: 02-late-order-state value
SELECT count() AS orders, sum(amount) AS amount
FROM (SELECT order_id, argMaxMerge(amount) AS amount FROM rmt_mv.order_state GROUP BY order_id);

-- order 20: two different rows with the same version, in two inserts
INSERT INTO rmt_mv.orders VALUES (20, '2026-11-01', 'paid', 500, 7);
INSERT INTO rmt_mv.orders VALUES (20, '2026-11-01', 'paid', 900, 7);

-- ReplacingMergeTree documents the tie: the last inserted row wins
-- probe: 02-tie-source-final value
SELECT amount FROM rmt_mv.orders FINAL WHERE order_id = 20;

-- argMax documents no order for ties
-- probe: 02-tie-order-state value
SELECT argMaxMerge(amount) AS amount FROM rmt_mv.order_state WHERE order_id = 20;

OPTIMIZE TABLE rmt_mv.order_state FINAL;

-- probe: 02-tie-order-state-merged value
SELECT argMaxMerge(amount) AS amount FROM rmt_mv.order_state WHERE order_id = 20;
