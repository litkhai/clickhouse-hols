-- ClickHouse 26.9 — LIMIT ... AFTER / UNTIL
--
--   LIMIT n AFTER cond
--   LIMIT UNTIL cond
--   LIMIT AFTER cond1 UNTIL cond2
--   LIMIT n AFTER cond ALL
--
-- Every LIMIT ClickHouse had before this counted positions: the first n rows,
-- n rows after skipping m. These four forms cut the stream at a row that
-- satisfies a condition instead, and they follow the stream order, so an
-- ORDER BY is what defines "before" and "after".
--
-- The distinction that makes them worth learning is against WHERE. WHERE tests
-- every row on its own and keeps the ones that pass, including the ones that
-- come after the interesting row. UNTIL stops at the first row that matches and
-- returns nothing past it.

SELECT '════════ 1. The four forms ════════' AS section;

-- UNION ALL does not expose its column aliases to a trailing ORDER BY, so the
-- whole union is wrapped before it is sorted. That is a ClickHouse quirk, not
-- something new in 26.9.
SELECT * FROM (
    SELECT 'LIMIT 3 AFTER number >= 5          ' AS form,
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number >= 5)) AS result
    UNION ALL
    SELECT 'LIMIT UNTIL number >= 3            ',
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT UNTIL number >= 3))
    UNION ALL
    SELECT 'LIMIT AFTER number >= 2 UNTIL >= 6 ',
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT AFTER number >= 2 UNTIL number >= 6))
    UNION ALL
    SELECT 'LIMIT 2 AFTER number IN (2,6) ALL  ',
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT 2 AFTER number IN (2, 6) ALL))
) ORDER BY form;

-- Expected:
--   LIMIT 2 AFTER number IN (2,6) ALL    [2,3,6,7]
--   LIMIT 3 AFTER number >= 5            [5,6,7]
--   LIMIT AFTER number >= 2 UNTIL >= 6   [2,3,4,5]
--   LIMIT UNTIL number >= 3              [0,1,2]
--
-- The ORDER BY on the outer query is only there to make the output stable;
-- each inner query carries its own ORDER BY, which is the one that matters.

SELECT '════════ 2. Why this is not WHERE ════════' AS section;

CREATE OR REPLACE TABLE events (n UInt8, lvl String) ENGINE = MergeTree ORDER BY n;
INSERT INTO events VALUES (1, 'ok'), (2, 'ok'), (3, 'error'), (4, 'ok'), (5, 'error'), (6, 'ok');

-- "Show me what happened up to the first error." WHERE cannot express it:
-- it has no notion of first, so rows 4 and 6 — which are fine on their own —
-- come back too.

SELECT * FROM (
    SELECT 'WHERE lvl != ''error''      ' AS query_,
           (SELECT groupArray(n) FROM (SELECT n FROM events WHERE lvl != 'error' ORDER BY n)) AS result
    UNION ALL
    SELECT 'LIMIT UNTIL lvl = ''error'' ',
           (SELECT groupArray(n) FROM (SELECT n FROM events ORDER BY n LIMIT UNTIL lvl = 'error'))
) ORDER BY query_;

-- Expected:
--   LIMIT UNTIL lvl = 'error'    [1,2]
--   WHERE lvl != 'error'         [1,2,4,6]

SELECT '════════ 3. The condition column need not be selected ════════' AS section;

-- lvl is nowhere in the SELECT list. The condition is evaluated against the
-- stream, not against the projection.

SELECT n FROM events ORDER BY n LIMIT UNTIL lvl = 'error';

SELECT '════════ 4. AFTER: the first match and what follows it ════════' AS section;

-- Two rows starting at the first error — the error itself is row 1 of the n.
SELECT * FROM (
    SELECT 'first error + 1 row' AS window_, groupArray(n) AS rows_
    FROM (SELECT n FROM events ORDER BY n LIMIT 2 AFTER lvl = 'error')
    UNION ALL
    -- ALL opens the same window at every error and unions them.
    SELECT 'every error + 1 row', groupArray(n)
    FROM (SELECT n FROM events ORDER BY n LIMIT 2 AFTER lvl = 'error' ALL)
) ORDER BY window_;

-- Expected:
--   every error + 1 row    [3,4,5,6]
--   first error + 1 row    [3,4]
--
-- This is the "give me the error and its next line" query that log readers
-- write by hand every day.

SELECT '════════ 5. Overlapping windows are unioned, not repeated ════════' AS section;

-- AFTER 2 opens [2,3,4] and AFTER 3 opens [3,4,5]. The union is [2,3,4,5];
-- 3 and 4 appear once, not twice.

SELECT groupArray(number) AS deduplicated
FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number IN (2, 3) ALL);

SELECT '════════ 6. When nothing matches ════════' AS section;

SELECT * FROM (
    SELECT 'AFTER never true → empty ' AS case_,
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number >= 99)) AS result
    UNION ALL
    SELECT 'UNTIL never true → all   ',
           (SELECT groupArray(number) FROM (SELECT number FROM numbers(5) ORDER BY number LIMIT UNTIL number >= 99))
) ORDER BY case_;

-- The asymmetry is the right one. AFTER has no window to open, so there is
-- nothing to return. UNTIL never finds a place to stop, so it returns the
-- whole stream.

SELECT '════════ 7. AFTER with no count runs to the end ════════' AS section;

SELECT groupArray(number) AS from_7_onwards
FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT AFTER number >= 7);

SELECT '════════ 8. It stops reading ════════' AS section;

-- UNTIL is not a filter applied after the fact; execution stops at the
-- boundary. Over 100 million rows with 1000-row blocks, the query touches one
-- block. Check read_rows in system.query_log after running this.

SELECT max(number) AS highest_row_read
FROM (SELECT number FROM numbers(100000000) LIMIT UNTIL number >= 10 SETTINGS max_block_size = 1000)
SETTINGS log_comment = 'limit_until_early_stop';

SYSTEM FLUSH LOGS;

SELECT read_rows, query_duration_ms
FROM system.query_log
WHERE log_comment = 'limit_until_early_stop' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

-- Expected: read_rows = 1000, one block out of a hundred million rows.

SELECT '════════ 9. OFFSET does not combine with it ════════' AS section;

-- LIMIT 3 AFTER cond OFFSET 1 is a syntax error: the grammar takes one branch
-- or the other. Skipping rows inside a boundary window means nesting the
-- query and applying a positional LIMIT outside it.

SELECT groupArray(number) AS skip_the_boundary_row
FROM (SELECT number FROM (SELECT number FROM numbers(10) ORDER BY number LIMIT 3 AFTER number >= 5) LIMIT 2 OFFSET 1);

-- Cleanup left commented so you can keep poking at the table.
-- DROP TABLE IF EXISTS events;
