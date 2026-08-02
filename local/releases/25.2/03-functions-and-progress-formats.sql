-- ClickHouse 25.2: stringCompare, initialQueryStartTime and the Progress Formats
-- New Features: stringCompare, initialQueryStartTime / initial_query_start_time,
--               JSONCompactEachRowWithProgress, JSONCompactStringsEachRowWithProgress
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-02

-- The two formats are what let the web UI show a live progress bar: the server
-- interleaves progress events with the rows instead of buffering them.

-- ============================================
-- 1. stringCompare
-- ============================================

SELECT '========== 1. Three-Way String Comparison ==========';

-- Returns -1, 0 or 1 — the comparator shape that sorting and diffing want,
-- rather than the two booleans you would otherwise combine.
SELECT
    stringCompare('apple', 'banana')  AS less,
    stringCompare('banana', 'apple')  AS greater,
    stringCompare('same', 'same')     AS equal;

-- ============================================
-- 2. Comparison Against the Operator Form
-- ============================================

SELECT '========== 2. Equivalent Written by Hand ==========';

SELECT
    a,
    b,
    stringCompare(a, b)                     AS three_way,
    multiIf(a < b, -1, a > b, 1, 0)         AS by_hand,
    stringCompare(a, b) = multiIf(a < b, -1, a > b, 1, 0) AS agrees
FROM
(
    SELECT arrayJoin([('alpha', 'beta'), ('beta', 'alpha'), ('gamma', 'gamma')]) AS pair,
           pair.1 AS a, pair.2 AS b
);

-- ============================================
-- 3. Sorting With a Comparator
-- ============================================

SELECT '========== 3. Ordering by the Comparator ==========';

DROP TABLE IF EXISTS words;

CREATE TABLE words (w String) ENGINE = MergeTree ORDER BY w;
INSERT INTO words VALUES ('delta'), ('alpha'), ('charlie'), ('bravo'), ('echo');

SELECT
    w,
    stringCompare(w, 'charlie') AS vs_charlie
FROM words
ORDER BY vs_charlie, w;

-- ============================================
-- 4. Bucketing by Comparison Result
-- ============================================

SELECT '========== 4. Before, Equal, After ==========';

SELECT
    multiIf(c = -1, 'before', c = 1, 'after', 'equal') AS position,
    count()                                            AS words,
    groupArray(w)                                      AS members
FROM (SELECT w, stringCompare(w, 'charlie') AS c FROM words)
GROUP BY position
ORDER BY position;

-- ============================================
-- 5. initialQueryStartTime
-- ============================================

SELECT '========== 5. Start Time of the Initiating Query ==========';

-- On a distributed query every shard reports the *initial* query's start time,
-- which makes it a stable key for correlating the parts of one request.
SELECT
    initialQueryStartTime()             AS started_at,
    toTypeName(started_at)              AS type,
    now() >= started_at                 AS not_in_the_future;

-- initial_query_start_time is the snake_case alias.
SELECT initialQueryStartTime() = initial_query_start_time() AS alias_matches;

-- ============================================
-- 6. Elapsed Time Inside the Query
-- ============================================

SELECT '========== 6. Elapsed Since the Query Started ==========';

SELECT
    initialQueryStartTime()                              AS started_at,
    dateDiff('second', initialQueryStartTime(), now())   AS seconds_elapsed
FROM numbers(3);

-- ============================================
-- 7. Tagging Results With Their Request
-- ============================================

SELECT '========== 7. Query Id Plus Start Time ==========';

SELECT
    currentQueryID()        AS query_id,
    initialQueryStartTime() AS started_at,
    w
FROM words
ORDER BY w
LIMIT 3;

-- ============================================
-- 8. The Progress Formats
-- ============================================

SELECT '========== 8. JSONCompactEachRowWithProgress ==========';

SELECT name, is_input, is_output
FROM system.formats
WHERE name IN ('JSONCompactEachRowWithProgress', 'JSONCompactStringsEachRowWithProgress')
ORDER BY name;

-- ============================================
-- 9. What the Format Emits
-- ============================================

SELECT '========== 9. Rows Interleaved With Progress Events ==========';

-- Each line is a JSON object tagged with its kind: "progress" events carry
-- read_rows / total_rows_to_read, "row" events carry the data. A client can
-- render a progress bar from the former while streaming the latter. On a
-- result this small the progress event lands at the end; on a long scan they
-- arrive throughout, which is the point of the format.
SELECT w FROM words ORDER BY w FORMAT JSONCompactEachRowWithProgress;

SELECT '========== 9b. The Strings Variant ==========';

-- The Strings variant renders every value as a string, which keeps large
-- integers exact for JSON consumers that would otherwise lose precision.
SELECT number, number * 1000000000000000000 AS big
FROM numbers(3)
FORMAT JSONCompactStringsEachRowWithProgress;

-- ============================================
-- 10. Progress on Something Worth Watching
-- ============================================

SELECT '========== 10. A Longer Scan ==========';

SELECT count() AS rows, max(number) AS largest
FROM numbers(5000000)
FORMAT JSONCompactEachRowWithProgress;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS words;

SELECT '========== Test Complete ==========';
SELECT 'The progress formats stream counters alongside rows, which is what a live UI needs.' AS summary;
