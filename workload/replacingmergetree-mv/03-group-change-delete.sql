-- 03 - a version that moves the row to another group, and a delete through is_deleted.
-- settings: allow_experimental_replacing_merge_with_cleanup, enable_replacing_merge_with_cleanup_for_min_age_to_force_merge
-- The per-status MV keeps the old group's row forever; filtering is_deleted = 0 in the MV keeps the deleted order.

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
ORDER BY order_id
-- table setting, needed only for OPTIMIZE … FINAL CLEANUP at the end
SETTINGS allow_experimental_replacing_merge_with_cleanup = 1;

-- MV without a filter
CREATE TABLE rmt_mv.by_status (status LowCardinality(String), orders Int64, amount Int64)
ENGINE = SummingMergeTree ORDER BY status;

CREATE MATERIALIZED VIEW rmt_mv.by_status_mv TO rmt_mv.by_status AS
SELECT status, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders GROUP BY status;

-- MV that drops delete markers
CREATE TABLE rmt_mv.by_status_live (status LowCardinality(String), orders Int64, amount Int64)
ENGINE = SummingMergeTree ORDER BY status;

CREATE MATERIALIZED VIEW rmt_mv.by_status_live_mv TO rmt_mv.by_status_live AS
SELECT status, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders WHERE is_deleted = 0 GROUP BY status;

INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'pending', 100, 1, 0), (2, '2026-11-01', 'pending', 200, 1, 0), (3, '2026-11-01', 'pending', 300, 1, 0);
-- order 1 is paid, order 2 is paid then refunded, order 3 is deleted
INSERT INTO rmt_mv.orders VALUES (1, '2026-11-01', 'paid', 100, 2, 0);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'paid', 200, 2, 0);
INSERT INTO rmt_mv.orders VALUES (2, '2026-11-01', 'refunded', 200, 3, 0);
INSERT INTO rmt_mv.orders VALUES (3, '2026-11-01', 'pending', 300, 2, 1);

-- truth: paid 1 / 100, refunded 1 / 200, pending none
-- probe: 03-source-final show
SELECT status, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders FINAL GROUP BY status ORDER BY status;

-- probe: 03-target-unfiltered show
SELECT status, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.by_status GROUP BY status ORDER BY status;

-- probe: 03-target-live show
SELECT status, sum(orders) AS orders, sum(amount) AS amount FROM rmt_mv.by_status_live GROUP BY status ORDER BY status;

-- FINAL hides a deleted key; without FINAL the marker row is still there, even after a merge
-- probe: 03-deleted-plain value
SELECT count() FROM rmt_mv.orders WHERE order_id = 3;

OPTIMIZE TABLE rmt_mv.orders FINAL;

-- probe: 03-deleted-after-optimize value
SELECT count() FROM rmt_mv.orders WHERE order_id = 3;

-- only OPTIMIZE … FINAL CLEANUP removes the marker
OPTIMIZE TABLE rmt_mv.orders FINAL CLEANUP;

-- probe: 03-deleted-after-cleanup value
SELECT count() FROM rmt_mv.orders WHERE order_id = 3;
