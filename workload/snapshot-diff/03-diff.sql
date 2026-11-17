-- 03-diff.sql: the diff of two snapshots, as rows a consumer can read.
--
-- new and changed: the current snapshot LEFT JOIN the previous one's (record_key, row_hash) USING record_key.
-- deleted: the previous snapshot LEFT ANTI JOIN the current one's keys.
-- The right side of each JOIN holds keys (and hashes) only, never the 25 fields.

TRUNCATE TABLE snapdiff.raw;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00');

-- truth, from the generator's rules (00-setup.sql): records only in the new snapshot, kept but different, gone
SELECT 'truth' AS t,
       countIf(number >= 10000) AS new,
       countIf(number < 10000 AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)) AS changed,
       countIf(number < 10000 AND number % 1000 < 3) AS deleted
FROM numbers(10000 + intDiv(10000, 200));

SELECT 'JOIN' AS t, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, row_hash AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c
    LEFT JOIN (SELECT record_key, row_hash AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);

-- the same classification in one GROUP BY over both snapshots (keys only, no JOIN)
SELECT 'GROUP BY' AS t, change_type, count() AS records
FROM
(
    SELECT record_key,
           multiIf(countIf(snapshot_id = '2026-11-17 09:00:00') = 0, 'new',
                   countIf(snapshot_id = '2026-11-17 10:00:00') = 0, 'deleted',
                   anyIf(row_hash, snapshot_id = '2026-11-17 10:00:00') != anyIf(row_hash, snapshot_id = '2026-11-17 09:00:00'), 'changed',
                   'same') AS change_type
    FROM snapdiff.raw
    WHERE snapshot_id IN ('2026-11-17 09:00:00', '2026-11-17 10:00:00')
    GROUP BY record_key
)
WHERE change_type != 'same'
GROUP BY change_type
ORDER BY change_type;

-- what changed in a changed record: the old and new value of each field that differs
SELECT c.record_key,
       arrayFilter(x -> x.2 IS DISTINCT FROM x.3,
           arrayZip(['f03', 'f06'], [p.f03, p.f06], [c.f03, c.f06])) AS changed_fields
FROM (SELECT record_key, f03, f06 FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c
INNER JOIN (SELECT record_key, f03, f06 FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p USING (record_key)
WHERE record_key IN ('K0000000007', 'K0000000011', 'K0000000107')
ORDER BY record_key;
