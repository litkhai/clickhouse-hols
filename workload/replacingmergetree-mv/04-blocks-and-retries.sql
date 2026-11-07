-- 04 - what the MV is handed: the insert block before optimize_on_insert, and retried blocks.
-- Insert deduplication (a retried identical block) is the one case where the MV can follow the source,
-- and only when the source has a deduplication window and deduplicate_blocks_in_dependent_materialized_views = 1.
-- settings: optimize_on_insert, insert_deduplicate, deduplicate_blocks_in_dependent_materialized_views, non_replicated_deduplication_window, replicated_deduplication_window

DROP DATABASE IF EXISTS rmt_mv;
CREATE DATABASE rmt_mv;

-- (a) two versions of one key inside one insert block
CREATE TABLE rmt_mv.orders (order_id UInt64, day Date, amount UInt64, ver UInt64)
ENGINE = ReplacingMergeTree(ver) ORDER BY order_id;

CREATE TABLE rmt_mv.daily_sum (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.daily_sum_mv TO rmt_mv.daily_sum AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders GROUP BY day;

INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 100, 1), (1, '2026-11-01', 150, 2), (2, '2026-11-01', 200, 1);

-- optimize_on_insert collapsed the block before it was written: the part holds 2 rows
-- probe: 04-inblock-source-rows value
SELECT count() FROM rmt_mv.orders;

-- the MV ran on the block as inserted: 3 rows, 450
-- probe: 04-inblock-target value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.daily_sum;

-- (b) a retried insert, source without a deduplication window (non-replicated MergeTree default)
CREATE TABLE rmt_mv.o_nowin (order_id UInt64, day Date, amount UInt64, ver UInt64)
ENGINE = ReplacingMergeTree(ver) ORDER BY order_id;

CREATE TABLE rmt_mv.d_nowin (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day;

CREATE MATERIALIZED VIEW rmt_mv.d_nowin_mv TO rmt_mv.d_nowin AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.o_nowin GROUP BY day;

INSERT INTO rmt_mv.o_nowin VALUES (1, '2026-11-01', 100, 1);
INSERT INTO rmt_mv.o_nowin VALUES (1, '2026-11-01', 100, 1);

-- probe: 04-retry-nowindow-source-final value
SELECT count() AS orders, sum(amount) AS amount FROM rmt_mv.o_nowin FINAL;

-- probe: 04-retry-nowindow-target value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.d_nowin;

-- (c) the same retry with a window on source and target (Replicated/Shared MergeTree have one by default)
CREATE TABLE rmt_mv.o_win (order_id UInt64, day Date, amount UInt64, ver UInt64)
ENGINE = ReplacingMergeTree(ver) ORDER BY order_id
SETTINGS non_replicated_deduplication_window = 100;

CREATE TABLE rmt_mv.d_win (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree ORDER BY day
SETTINGS non_replicated_deduplication_window = 100;

CREATE MATERIALIZED VIEW rmt_mv.d_win_mv TO rmt_mv.d_win AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.o_win GROUP BY day;

INSERT INTO rmt_mv.o_win VALUES (1, '2026-11-01', 100, 1);
INSERT INTO rmt_mv.o_win VALUES (1, '2026-11-01', 100, 1);

-- probe: 04-retry-window-target value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.d_win;

-- a different order whose MV output block is byte-identical must still count
INSERT INTO rmt_mv.o_win VALUES (2, '2026-11-01', 100, 1);

-- probe: 04-same-mv-output-target value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.d_win;

-- the retry again, with deduplicate_blocks_in_dependent_materialized_views = 0
INSERT INTO rmt_mv.o_win SETTINGS deduplicate_blocks_in_dependent_materialized_views = 0 VALUES (3, '2026-11-01', 100, 1);
INSERT INTO rmt_mv.o_win SETTINGS deduplicate_blocks_in_dependent_materialized_views = 0 VALUES (3, '2026-11-01', 100, 1);

-- probe: 04-retry-dbidmv0-source value
SELECT count() FROM rmt_mv.o_win;

-- truth 3 orders / 300; the target got the retry
-- probe: 04-retry-dbidmv0-target value
SELECT sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.d_win;
