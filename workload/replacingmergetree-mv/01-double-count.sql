-- 01 - an incremental MV over ReplacingMergeTree counts every version it was sent.
-- The source collapses versions at merge (or FINAL); the MV ran once per insert block and never sees that merge.
-- settings: deduplicate_blocks_in_dependent_materialized_views, optimize_on_insert

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

-- target 1: SummingMergeTree per day (the most common shape)
CREATE TABLE rmt_mv.daily_sum
(
    day    Date,
    orders UInt64,
    amount UInt64
)
ENGINE = SummingMergeTree
ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_sum_mv TO rmt_mv.daily_sum AS
SELECT day, count() AS orders, sum(amount) AS amount
FROM rmt_mv.orders
GROUP BY day;

-- target 2: AggregatingMergeTree with uniqExact(order_id) — fixes the order count, not the sum
CREATE TABLE rmt_mv.daily_agg
(
    day    Date,
    orders AggregateFunction(uniqExact, UInt64),
    amount AggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_agg_mv TO rmt_mv.daily_agg AS
SELECT day, uniqExactState(order_id) AS orders, sumState(amount) AS amount
FROM rmt_mv.orders
GROUP BY day;

-- three orders, version 1
INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'paid', 100, 1), (2, '2026-11-01', 'paid', 200, 1), (3, '2026-11-01', 'paid', 300, 1);
-- order 1 corrected to 150 (v2); order 2 corrected twice (v2 = 250, v3 = 220)
INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'paid', 150, 2);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'paid', 250, 2);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'paid', 220, 3);

-- truth: 3 orders, 150 + 220 + 300 = 670
-- probe: 01-source-final value
SELECT count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL;

-- probe: 01-source-plain value
SELECT count() AS orders, sum(amount) AS amount FROM rmt_mv.orders;

-- probe: 01-target-sum value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_sum;

-- probe: 01-target-agg value
SELECT uniqExactMerge(orders) AS orders, sumMerge(amount) AS amount FROM rmt_mv.daily_agg;

-- the MV's own input: rows it was handed, one row per insert block
-- probe: 01-target-rows show
SELECT day, orders, amount, _part FROM rmt_mv.daily_sum ORDER BY _part;

-- merge the source completely
OPTIMIZE TABLE rmt_mv.orders FINAL;

-- probe: 01-after-optimize-source-plain value
SELECT count() AS orders, sum(amount) AS amount FROM rmt_mv.orders;

-- probe: 01-after-optimize-target-sum value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_sum;

OPTIMIZE TABLE rmt_mv.daily_sum FINAL;

-- merging the target does not help either: it sums what it was given
-- probe: 01-after-optimize-both-target-sum value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_sum;
