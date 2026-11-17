-- 01-boundary.sql: a snapshot arrives in many inserts, so ingestion_timestamp cannot delimit it.
--
-- Every hour the producer starts at hh:56 and the sink writes the snapshot over 8 minutes.
-- The 09:00 snapshot lands 09:56-10:04, the 10:00 snapshot 10:56-11:04; one batch of the 10:00
-- snapshot is delivered again at 11:20 (a sink retry). ingestion_timestamp is set explicitly to
-- simulate those times; snapshot_id is what the producer stamps on every record.

TRUNCATE TABLE snapdiff.raw;

INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp, ingestion_timestamp)
SELECT *, toDateTime64('2026-11-17 09:56:00', 3) + toIntervalMillisecond(cityHash64(record_key, snapshot_id) % 480000)
FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');

INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp, ingestion_timestamp)
SELECT *, toDateTime64('2026-11-17 10:56:00', 3) + toIntervalMillisecond(cityHash64(record_key, snapshot_id) % 480000)
FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00');

-- the retry: the records of the first minute of the 10:00 load, again
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp, ingestion_timestamp)
SELECT *, toDateTime64('2026-11-17 11:20:00', 3)
FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00')
WHERE cityHash64(record_key, snapshot_id) % 480000 < 60000;

-- what an hourly window on ingestion_timestamp holds
SELECT toStartOfHour(ingestion_timestamp) AS ingestion_hour,
       count() AS rows, uniqExact(record_key) AS records,
       groupUniqArray(toString(snapshot_id)) AS snapshots_inside
FROM snapdiff.raw
GROUP BY ingestion_hour
ORDER BY ingestion_hour;

-- what snapshot_id holds
SELECT snapshot_id, count() AS rows, uniqExact(record_key) AS records,
       min(ingestion_timestamp) AS first_row, max(ingestion_timestamp) AS last_row
FROM snapdiff.raw
GROUP BY snapshot_id
ORDER BY snapshot_id;

-- truth, from the generator's rules (00-setup.sql): records only in the new snapshot, kept but different, gone
SELECT 'truth' AS t,
       countIf(number >= 10000) AS new,
       countIf(number < 10000 AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)) AS changed,
       countIf(number < 10000 AND number % 1000 < 3) AS deleted
FROM numbers(10000 + intDiv(10000, 200));

-- the diff of the 11:00 ingestion hour against the 10:00 one (no snapshot_id)
SELECT 'by ingestion hour' AS t, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, row_hash AS h FROM snapdiff.raw WHERE toStartOfHour(ingestion_timestamp) = '2026-11-17 11:00:00' LIMIT 1 BY record_key) AS c
    LEFT JOIN (SELECT record_key, row_hash AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE toStartOfHour(ingestion_timestamp) = '2026-11-17 10:00:00' LIMIT 1 BY record_key) AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE toStartOfHour(ingestion_timestamp) = '2026-11-17 10:00:00' LIMIT 1 BY record_key) AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE toStartOfHour(ingestion_timestamp) = '2026-11-17 11:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);

-- the same diff by snapshot_id, without and with dropping the re-delivered duplicates
SELECT 'by snapshot_id, no dedupe' AS t, * FROM (
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
SELECT 'by snapshot_id, LIMIT 1 BY record_key' AS t, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, row_hash AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00' LIMIT 1 BY record_key) AS c
    LEFT JOIN (SELECT record_key, row_hash AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00' LIMIT 1 BY record_key) AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00' LIMIT 1 BY record_key) AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);
