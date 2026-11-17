-- 02-row-hash.sql: which hash finds the changed records.
--
-- The hash covers the 25 business fields only. record_key is the join key, ingestion_timestamp is set by the
-- sink, and event_timestamp moves on every snapshot, so none of them belongs in it.

-- the functions on literals
SELECT cityHash64(NULL::Nullable(String), 'a') AS variadic_with_null,
       cityHash64(tuple(NULL::Nullable(String), 'a')) AS tuple_with_null,
       cityHash64(tuple(''::Nullable(String), 'a')) AS tuple_with_empty,
       cityHash64(tuple('ab', 'c')) = cityHash64(tuple('a', 'bc')) AS tuple_shift_collides,
       cityHash64(concat('ab', 'c')) = cityHash64(concat('a', 'bc')) AS concat_shift_collides,
       cityHash64(ifNull(NULL::Nullable(String), '')) = cityHash64('') AS ifnull_null_equals_empty;

-- a clean pair of snapshots
TRUNCATE TABLE snapdiff.raw;
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 0, sid = '2026-11-17 09:00:00');
INSERT INTO snapdiff.raw (snapshot_id, record_key, f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp) SELECT * FROM snapdiff.gen(n = 10000, v = 1, sid = '2026-11-17 10:00:00');

-- truth, from the generator's rules (00-setup.sql): records only in the new snapshot, kept but different, gone
SELECT 'truth' AS t,
       countIf(number >= 10000) AS new,
       countIf(number < 10000 AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)) AS changed,
       countIf(number < 10000 AND number % 1000 < 3) AS deleted
FROM numbers(10000 + intDiv(10000, 200));

-- rows where the variadic form is NULL (any of the five nullable fields is NULL)
SELECT snapshot_id, count() AS rows, countIf(cityHash64(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25) IS NULL) AS variadic_hash_is_null
FROM snapdiff.raw GROUP BY snapshot_id ORDER BY snapshot_id;

-- A: tuple of the 25 business fields (the MATERIALIZED row_hash column)
SELECT 'A tuple(f01..f25)' AS hash, * FROM (
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
-- B: variadic cityHash64(f01, ..., f25): NULL whenever one field is NULL, and NULL != x is not true
SELECT 'B cityHash64(f01, ..., f25)' AS hash, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, cityHash64(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25) AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c
    LEFT JOIN (SELECT record_key, cityHash64(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25) AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);
-- C: ifNull(f, '') before hashing: NULL and '' become the same value
SELECT 'C ifNull(f, \'\')' AS hash, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, cityHash64(tuple(ifNull(f01, ''), ifNull(f02, ''), ifNull(f03, ''), ifNull(f04, ''), ifNull(f05, ''), ifNull(f06, ''), ifNull(f07, ''), ifNull(f08, ''), ifNull(f09, ''), ifNull(f10, ''), ifNull(f11, ''), ifNull(f12, ''), ifNull(f13, ''), ifNull(f14, ''), ifNull(f15, ''), ifNull(f16, ''), ifNull(f17, ''), ifNull(f18, ''), ifNull(f19, ''), ifNull(f20, ''), ifNull(f21, ''), ifNull(f22, ''), ifNull(f23, ''), ifNull(f24, ''), ifNull(f25, ''))) AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c
    LEFT JOIN (SELECT record_key, cityHash64(tuple(ifNull(f01, ''), ifNull(f02, ''), ifNull(f03, ''), ifNull(f04, ''), ifNull(f05, ''), ifNull(f06, ''), ifNull(f07, ''), ifNull(f08, ''), ifNull(f09, ''), ifNull(f10, ''), ifNull(f11, ''), ifNull(f12, ''), ifNull(f13, ''), ifNull(f14, ''), ifNull(f15, ''), ifNull(f16, ''), ifNull(f17, ''), ifNull(f18, ''), ifNull(f19, ''), ifNull(f20, ''), ifNull(f21, ''), ifNull(f22, ''), ifNull(f23, ''), ifNull(f24, ''), ifNull(f25, ''))) AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);
-- D: event_timestamp in the hash: it moves on every snapshot
SELECT 'D tuple(f01..f25, event_timestamp)' AS hash, * FROM (
SELECT change_type, count() AS records
FROM
(
    SELECT if(p.in_prev = 0, 'new', 'changed') AS change_type
    FROM (SELECT record_key, cityHash64(tuple(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp)) AS h FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c
    LEFT JOIN (SELECT record_key, cityHash64(tuple(f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25, event_timestamp)) AS prev_h, 1 AS in_prev FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'deleted'
    FROM (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 09:00:00') AS p
    LEFT ANTI JOIN (SELECT record_key FROM snapdiff.raw WHERE snapshot_id = '2026-11-17 10:00:00') AS c USING (record_key)
)
GROUP BY change_type
ORDER BY change_type
);
