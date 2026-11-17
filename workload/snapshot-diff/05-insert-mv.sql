-- 05-insert-mv.sql: detecting changes at insert time instead, with a ReplacingMergeTree state table.
--
-- state keeps the last row_hash per record_key. mv_detect joins every inserted block to state and writes the
-- records that are new or whose hash differs; mv_state writes the block's hashes into state.
-- Deletes cannot be seen this way: a deleted record is a row that never arrives.

DROP VIEW IF EXISTS snapdiff.diff_rmv;
DROP VIEW IF EXISTS snapdiff.diff_rmv_naive;
DROP VIEW IF EXISTS snapdiff.mv_detect;
DROP VIEW IF EXISTS snapdiff.mv_state;
DROP TABLE IF EXISTS snapdiff.state;
DROP TABLE IF EXISTS snapdiff.changes_mv;
TRUNCATE TABLE snapdiff.raw;

CREATE TABLE snapdiff.state
(
    record_key String,
    row_hash UInt64,
    snapshot_id DateTime
)
ENGINE = ReplacingMergeTree(snapshot_id)
ORDER BY record_key;

CREATE TABLE snapdiff.changes_mv AS snapdiff.changes;

CREATE MATERIALIZED VIEW snapdiff.mv_detect TO snapdiff.changes_mv AS
SELECT r.snapshot_id AS snapshot_id, s.prev_snapshot AS prev_snapshot_id,
       if(s.in_state = 0, 'new', 'changed') AS change_type,
       r.record_key AS record_key, r.f01 AS f01, r.f02 AS f02, r.f03 AS f03, r.f04 AS f04, r.f05 AS f05, r.f06 AS f06, r.f07 AS f07, r.f08 AS f08, r.f09 AS f09, r.f10 AS f10, r.f11 AS f11, r.f12 AS f12, r.f13 AS f13, r.f14 AS f14, r.f15 AS f15, r.f16 AS f16, r.f17 AS f17, r.f18 AS f18, r.f19 AS f19, r.f20 AS f20, r.f21 AS f21, r.f22 AS f22, r.f23 AS f23, r.f24 AS f24, r.f25 AS f25
FROM snapdiff.raw AS r
LEFT JOIN (SELECT record_key, argMax(row_hash, snapshot_id) AS prev_hash, max(snapshot_id) AS prev_snapshot, 1 AS in_state
           FROM snapdiff.state GROUP BY record_key) AS s USING (record_key)
WHERE s.in_state = 0 OR r.row_hash != s.prev_hash;

CREATE MATERIALIZED VIEW snapdiff.mv_state TO snapdiff.state AS
SELECT record_key, row_hash, snapshot_id FROM snapdiff.raw;

SELECT name, value FROM system.settings WHERE name = 'parallel_view_processing';

-- snapshot 09:00 in one insert, then 10:00 in 10 inserts of about 1,000 records (one per sink batch)
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 0;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 1;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 2;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 3;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 4;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 5;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 6;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 7;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 8;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 = 9;

-- truth, from the generator's rules (00-setup.sql): records only in the new snapshot, kept but different, gone
SELECT 'truth' AS t,
       countIf(number >= 10000) AS new,
       countIf(number < 10000 AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)) AS changed,
       countIf(number < 10000 AND number % 1000 < 3) AS deleted
FROM numbers(10000 + intDiv(10000, 200));

SELECT 'insert-time MV' AS t, snapshot_id, change_type, count() AS records
FROM snapdiff.changes_mv GROUP BY ALL ORDER BY snapshot_id, change_type;

