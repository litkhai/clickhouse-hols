-- 04-rmv.sql: the diff as a refreshable MV that appends to snapdiff.changes, and the partial-snapshot race.
--
-- diff_rmv (guarded): compares the oldest snapshot that is not compared yet, only when the manifest row for it has
-- arrived and all its records are loaded, and writes one 'end' row per snapshot. The next refresh starts after
-- the last 'end' row, so a refresh that finds nothing to do writes nothing.
-- diff_rmv_naive: compares the newest snapshot_id in raw with the one before, whatever has arrived.

TRUNCATE TABLE snapdiff.raw;
TRUNCATE TABLE snapdiff.manifest;
TRUNCATE TABLE snapdiff.changes;
DROP VIEW IF EXISTS snapdiff.diff_rmv;
DROP VIEW IF EXISTS snapdiff.diff_rmv_naive;
DROP TABLE IF EXISTS snapdiff.changes_naive;
CREATE TABLE snapdiff.changes_naive AS snapdiff.changes;

-- snapshot 09:00: all records, then its manifest row
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 09:00:00', uniqExact(record_key) FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00';

CREATE MATERIALIZED VIEW snapdiff.diff_rmv
REFRESH EVERY 1 HOUR OFFSET 30 MINUTE
APPEND TO snapdiff.changes
AS
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

CREATE MATERIALIZED VIEW snapdiff.diff_rmv_naive
REFRESH EVERY 1 HOUR OFFSET 30 MINUTE
APPEND TO snapdiff.changes_naive
AS
WITH
    (SELECT max(snapshot_id) FROM snapdiff.raw) AS cur,
    (SELECT max(snapshot_id) FROM snapdiff.raw WHERE snapshot_id < cur) AS prev,
    prev > toDateTime(0) AS compare
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
);

-- a refreshable MV refreshes once when it is created; wait for that one
SYSTEM WAIT VIEW snapdiff.diff_rmv;
SYSTEM WAIT VIEW snapdiff.diff_rmv_naive;

-- snapshot 10:00, 60 % loaded (the sink is still writing) when the refresh runs
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp)
SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 < 6;

SYSTEM REFRESH VIEW snapdiff.diff_rmv;      SYSTEM WAIT VIEW snapdiff.diff_rmv;
SYSTEM REFRESH VIEW snapdiff.diff_rmv_naive; SYSTEM WAIT VIEW snapdiff.diff_rmv_naive;

-- truth, from the generator's rules (00-setup.sql): records only in the new snapshot, kept but different, gone
SELECT 'truth' AS t,
       countIf(number >= 10000) AS new,
       countIf(number < 10000 AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)) AS changed,
       countIf(number < 10000 AND number % 1000 < 3) AS deleted
FROM numbers(10000 + intDiv(10000, 200));

SELECT * FROM (
SELECT 'after a refresh on a 60 % load' AS t, 'naive' AS mv, snapshot_id, change_type, count() AS records
FROM snapdiff.changes_naive GROUP BY ALL
UNION ALL
SELECT 'after a refresh on a 60 % load', 'guarded', snapshot_id, change_type, count()
FROM snapdiff.changes GROUP BY ALL
)
ORDER BY mv, snapshot_id, change_type;

-- the rest of the load, then the producer's manifest row
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp)
SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00') WHERE cityHash64(record_key) % 10 >= 6;
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 10:00:00', 10020;

SYSTEM REFRESH VIEW snapdiff.diff_rmv;      SYSTEM WAIT VIEW snapdiff.diff_rmv;
SYSTEM REFRESH VIEW snapdiff.diff_rmv_naive; SYSTEM WAIT VIEW snapdiff.diff_rmv_naive;

SELECT * FROM (
SELECT 'after the load completed' AS t, 'naive' AS mv, snapshot_id, change_type, count() AS records
FROM snapdiff.changes_naive GROUP BY ALL
UNION ALL
SELECT 'after the load completed', 'guarded', snapshot_id, change_type, count()
FROM snapdiff.changes GROUP BY ALL
)
ORDER BY mv, snapshot_id, change_type;

-- two more refreshes of the guarded MV with nothing new: they run, and write nothing
SYSTEM REFRESH VIEW snapdiff.diff_rmv;      SYSTEM WAIT VIEW snapdiff.diff_rmv;
SYSTEM REFRESH VIEW snapdiff.diff_rmv;      SYSTEM WAIT VIEW snapdiff.diff_rmv;

-- snapshot 11:00 equals 10:00 except event_timestamp: compared, no change rows, one 'end' row
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 11:00:00');
INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '2026-11-17 11:00:00', 10020;
SYSTEM REFRESH VIEW snapdiff.diff_rmv; SYSTEM WAIT VIEW snapdiff.diff_rmv;

SELECT snapshot_id, prev_snapshot_id, change_type, count() AS records, max(detected_at) AS detected_at
FROM snapdiff.changes GROUP BY ALL ORDER BY snapshot_id, change_type;

-- what a consumer runs: everything after the last snapshot it has read, up to the last 'end' row
SELECT snapshot_id, change_type, record_key, f03, f06
FROM snapdiff.changes
WHERE snapshot_id > '2026-11-17 09:00:00'
  AND snapshot_id <= (SELECT max(snapshot_id) FROM snapdiff.changes WHERE change_type = 'end')
  AND change_type != 'end'
ORDER BY snapshot_id, change_type, record_key
LIMIT 5;

-- the schedule, on every replica (the refresh runs on one of them)
SELECT replace(hostName(), substring(hostName(), 1, position(hostName(), '-server-') + 7), '') AS replica,
       view, status, last_success_time, next_refresh_time, read_rows, written_rows
FROM clusterAllReplicas(default, system.view_refreshes)
WHERE database = 'snapdiff'
ORDER BY view, replica;

-- every refresh of both MVs in this file and what it wrote (query_log on all replicas), then the parts per refresh
-- (one part means a reader sees all of a refresh or none of it)
SYSTEM FLUSH LOGS ON CLUSTER default;
SELECT event_time, extract(query, '^INSERT INTO (snapdiff\.[a-z_]+) ') AS target, written_rows, exception_code
FROM clusterAllReplicas(default, system.query_log)
WHERE event_date = today() AND event_time > now() - INTERVAL 3 MINUTE AND type != 'QueryStart'
  AND (query LIKE 'INSERT INTO snapdiff.changes %' OR query LIKE 'INSERT INTO snapdiff.changes_naive %')
ORDER BY event_time_microseconds;

SELECT query_id, count() AS new_parts, sum(rows) AS rows
FROM clusterAllReplicas(default, system.part_log)
WHERE database = 'snapdiff' AND table = 'changes' AND event_type = 'NewPart' AND event_date = today()
  AND event_time > now() - INTERVAL 3 MINUTE
GROUP BY query_id
ORDER BY min(event_time);
