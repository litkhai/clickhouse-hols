-- 06-ttl.sql: keep only recent snapshots in raw, and what a too-short TTL does to the diff.
--
-- raw is partitioned by snapshot_id, so a TTL on snapshot_id with ttl_only_drop_parts = 1 drops whole
-- snapshots instead of rewriting parts. Snapshot ids here are relative to now() so the TTL fires.

DROP TABLE IF EXISTS snapdiff.raw_ttl;
CREATE TABLE snapdiff.raw_ttl AS snapdiff.raw
ENGINE = MergeTree
PARTITION BY snapshot_id
ORDER BY (snapshot_id, record_key)
TTL snapshot_id + INTERVAL 3 HOUR
SETTINGS ttl_only_drop_parts = 1;

-- six hourly snapshots of 1,000 records, the oldest five hours ago
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 1, sid = toStartOfHour(now()) - INTERVAL 5 HOUR);
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 0, sid = toStartOfHour(now()) - INTERVAL 4 HOUR);
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 1, sid = toStartOfHour(now()) - INTERVAL 3 HOUR);
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 0, sid = toStartOfHour(now()) - INTERVAL 2 HOUR);
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 1, sid = toStartOfHour(now()) - INTERVAL 1 HOUR);
INSERT INTO snapdiff.raw_ttl (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 1000, v = 0, sid = toStartOfHour(now()) - INTERVAL 0 HOUR);

-- TTL is applied when parts merge; force it now
OPTIMIZE TABLE snapdiff.raw_ttl FINAL;

SELECT dateDiff('hour', snapshot_id, toStartOfHour(now())) AS hours_ago, count() AS rows
FROM snapdiff.raw_ttl GROUP BY snapshot_id ORDER BY snapshot_id;

SELECT engine_full LIKE '%TTL snapshot_id + toIntervalHour(3)%' AS has_ttl
FROM system.tables WHERE database = 'snapdiff' AND name = 'raw_ttl';

-- the same TTL on the changes table, for how long consumers may fall behind
ALTER TABLE snapdiff.changes MODIFY TTL snapshot_id + INTERVAL 7 DAY;

-- a previous snapshot that is gone from raw (dropped by a TTL shorter than the diff's backlog):
-- the guarded MV does not compare against it, so it reports nothing instead of every record as new.
-- Here the 10:00 and 11:00 snapshots of 04 are reloaded, 10:00 is compared, and then 10:00 is dropped before 11:00 is compared.
TRUNCATE TABLE snapdiff.raw; TRUNCATE TABLE snapdiff.manifest; TRUNCATE TABLE snapdiff.changes;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00');
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 09:00:00', 10000;
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 10:00:00', 10020;
CREATE MATERIALIZED VIEW snapdiff.diff_rmv REFRESH EVERY 1 HOUR OFFSET 30 MINUTE APPEND TO snapdiff.changes AS
WITH
    (SELECT max(snapshot_id) FROM snapdiff.changes WHERE change_type = 'end') AS done,
    (SELECT min(snapshot_id) FROM snapdiff.manifest WHERE snapshot_id > done) AS cur,
    (SELECT max(snapshot_id) FROM snapdiff.manifest WHERE snapshot_id < cur) AS prev,
    (SELECT any(expected_rows) FROM snapdiff.manifest WHERE snapshot_id = cur) AS cur_expected,
    (SELECT any(expected_rows) FROM snapdiff.manifest WHERE snapshot_id = prev) AS prev_expected,
    (SELECT uniqExact(record_key) FROM snapdiff.raw WHERE snapshot_id = cur) AS cur_loaded,
    (SELECT uniqExact(record_key) FROM snapdiff.raw WHERE snapshot_id = prev) AS prev_loaded,
    -- ready: an uncompared snapshot whose manifest row has arrived and whose records are all loaded,
    -- and a previous snapshot that is still complete in raw (not dropped by TTL)
    cur > done AND cur_loaded >= cur_expected AND (prev = toDateTime(0) OR prev_loaded >= prev_expected) AS ready,
    ready AND prev > toDateTime(0) AS compare
SELECT snapshot_id, prev_snapshot_id, change_type, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25
FROM
(
    -- step 2: the full rows of the changed keys only: new and changed from cur, deleted from prev
    SELECT cur AS snapshot_id, prev AS prev_snapshot_id, CAST(k.change_type AS Enum8('new' = 1, 'changed' = 2, 'deleted' = 3, 'end' = 9)) AS change_type,
           r.record_key AS record_key, r.f01, r.f02, r.f03, r.f04, r.f05, r.f06, r.f07, r.f08, r.f09, r.f10, r.f11, r.f12, r.f13, r.f14, r.f15, r.f16, r.f17, r.f18, r.f19, r.f20, r.f21, r.f22, r.f23, r.f24, r.f25
    FROM (SELECT snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25 FROM snapdiff.raw WHERE compare AND snapshot_id IN (prev, cur)) AS r
    INNER JOIN
    (
        -- step 1: classify every key of both snapshots by presence and row_hash (keys and hashes only)
        SELECT record_key,
               multiIf(countIf(snapshot_id = prev) = 0, 'new',
                       countIf(snapshot_id = cur) = 0, 'deleted',
                       anyIf(row_hash, snapshot_id = cur) != anyIf(row_hash, snapshot_id = prev), 'changed',
                       'same') AS change_type
        FROM snapdiff.raw
        WHERE compare AND snapshot_id IN (prev, cur)
        GROUP BY record_key
        HAVING change_type != 'same'
    ) AS k USING (record_key)
    WHERE (r.snapshot_id = cur AND k.change_type IN ('new', 'changed')) OR (r.snapshot_id = prev AND k.change_type = 'deleted')
    LIMIT 1 BY record_key
    UNION ALL
    -- one 'end' row per compared snapshot (the first one is only a baseline): where the next refresh starts,
    -- and the signal for consumers
    SELECT cur, prev, 'end', '', NULL AS f01, NULL AS f02, NULL AS f03, NULL AS f04, NULL AS f05, NULL AS f06, NULL AS f07, NULL AS f08, NULL AS f09, NULL AS f10, NULL AS f11, NULL AS f12, NULL AS f13, NULL AS f14, NULL AS f15, NULL AS f16, NULL AS f17, NULL AS f18, NULL AS f19, NULL AS f20, NULL AS f21, NULL AS f22, NULL AS f23, NULL AS f24, NULL AS f25
    WHERE ready
);
SYSTEM WAIT VIEW snapdiff.diff_rmv;
SYSTEM REFRESH VIEW snapdiff.diff_rmv; SYSTEM WAIT VIEW snapdiff.diff_rmv;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 11:00:00');
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 11:00:00', 10000;
ALTER TABLE snapdiff.raw DROP PARTITION '2026-11-17 10:00:00';
SYSTEM REFRESH VIEW snapdiff.diff_rmv; SYSTEM WAIT VIEW snapdiff.diff_rmv;
SELECT 'prev dropped' AS t, snapshot_id, change_type, count() AS records FROM snapdiff.changes GROUP BY ALL ORDER BY snapshot_id, change_type;
-- what a diff against the dropped snapshot would report
SELECT 'diff against an empty prev' AS t, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, row_hash AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 11:00:00') AS c
    LEFT JOIN (SELECT record_key, row_hash AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 11:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);
DROP VIEW snapdiff.diff_rmv;
