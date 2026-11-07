-- errors/01 - FINAL in the SELECT of an incremental MV.
-- Expected to fail (Code 397 on 26.8 and 26.10): the MV query runs over the insert block, so there is nothing for FINAL to merge against.

DROP DATABASE IF EXISTS rmt_mv;
CREATE DATABASE rmt_mv;

CREATE TABLE rmt_mv.orders (order_id UInt64, day Date, amount UInt64, ver UInt64)
ENGINE = ReplacingMergeTree(ver) ORDER BY order_id;

CREATE TABLE rmt_mv.daily_sum (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

-- probe: e01-mv-with-final
CREATE MATERIALIZED VIEW rmt_mv.daily_sum_mv TO rmt_mv.daily_sum AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL GROUP BY day;
