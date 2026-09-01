-- ClickHouse 26.8 — GROUPS window frame mode
--
--   OVER (ORDER BY x GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
--
-- SQL has three ways to say how wide a window frame is, and until 26.8
-- ClickHouse had two of them:
--
--   ROWS    count physical rows
--   RANGE   count by value distance from the current row
--   GROUPS  count peer groups — rows sharing the same ORDER BY value
--
-- GROUPS is the one you want whenever ties are meaningful and the gaps
-- between values are not.

SELECT '════════ 1. All three, side by side ════════' AS section;

-- The data is chosen so the three answers differ. Values 1, 5, 5, 100:
-- a tie in the middle, and a large gap at the end.
--
--   ROWS   1 PRECEDING/FOLLOWING = the physically adjacent rows
--   RANGE  1 PRECEDING/FOLLOWING = rows whose value is within ±1
--   GROUPS 1 PRECEDING/FOLLOWING = the previous peer group, this one, the next

WITH d AS (SELECT arrayJoin([1, 5, 5, 100]) AS n)
SELECT n,
       count() OVER w_rows   AS rows_frame,
       count() OVER w_range  AS range_frame,
       count() OVER w_groups AS groups_frame
FROM d
WINDOW w_rows   AS (ORDER BY n ROWS   BETWEEN 1 PRECEDING AND 1 FOLLOWING),
       w_range  AS (ORDER BY n RANGE  BETWEEN 1 PRECEDING AND 1 FOLLOWING),
       w_groups AS (ORDER BY n GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
ORDER BY n;

-- Expected:
--    n  | rows | range | groups
--    1  |   2  |   1   |   3
--    5  |   3  |   2   |   4
--    5  |   3  |   2   |   4
--   100 |   2  |   1   |   3
--
-- RANGE collapses at the gap — nothing is within ±1 of 100, so the frame is
-- just the row itself. GROUPS does not care how far away 100 is, only that it
-- is the next distinct value.

SELECT '════════ 2. Where RANGE and GROUPS agree ════════' AS section;

-- With values one apart and no gaps, RANGE and GROUPS coincide. This is why
-- the difference is easy to miss until it bites: on evenly spaced data they
-- are the same function.

WITH d AS (SELECT arrayJoin([1, 2, 3, 3, 3, 4, 5]) AS n)
SELECT n,
       count() OVER (ORDER BY n RANGE  BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS range_frame,
       count() OVER (ORDER BY n GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS groups_frame
FROM d ORDER BY n;

SELECT '════════ 3. A case where GROUPS is the correct answer ════════' AS section;

-- Ranked results with ties. "Compare each score against the ranks either side
-- of it" is a GROUPS question: you mean the neighbouring rank, not a score
-- one point away, and not a fixed number of rows.

CREATE OR REPLACE TABLE scores (player String, score UInt32) ENGINE = Memory;
INSERT INTO scores VALUES
    ('a', 100), ('b', 100), ('c', 100),   -- three-way tie for first
    ('d',  80),
    ('e',  55), ('f', 55),                -- two-way tie
    ('g',  10);

SELECT player, score,
       -- everyone in the adjacent ranks, ties included
       groupArray(player) OVER (ORDER BY score DESC
                                GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS neighbour_ranks,
       -- what ROWS would have given you: an arbitrary slice through the ties
       groupArray(player) OVER (ORDER BY score DESC
                                ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)   AS neighbour_rows
FROM scores
ORDER BY score DESC, player;

SELECT '════════ 4. Frame bounds GROUPS accepts ════════' AS section;

SELECT n,
       count() OVER (ORDER BY n GROUPS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)     AS cumulative,
       count() OVER (ORDER BY n GROUPS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)     AS remaining,
       count() OVER (ORDER BY n GROUPS BETWEEN 2 PRECEDING AND 0 FOLLOWING)             AS last_3_groups
FROM (SELECT arrayJoin([1, 1, 2, 3, 3, 4]) AS n)
ORDER BY n;

SELECT '════════ 5. CURRENT ROW means the whole peer group ════════' AS section;

-- This is the detail that surprises people. Under GROUPS (and RANGE),
-- CURRENT ROW is not one row — it is every row tied with it. Under ROWS it is
-- literally the one row.

WITH d AS (SELECT arrayJoin([7, 7, 7]) AS n)
SELECT n,
       count() OVER (ORDER BY n GROUPS BETWEEN CURRENT ROW AND CURRENT ROW) AS groups_current,
       count() OVER (ORDER BY n ROWS   BETWEEN CURRENT ROW AND CURRENT ROW) AS rows_current
FROM d;

-- Cleanup left commented so you can keep poking at the table.
-- DROP TABLE IF EXISTS scores;
