-- ClickHouse 26.8 — Pipe operators
--
--   FROM t |> WHERE x > 1 |> AGGREGATE sum(y) GROUP BY z |> ORDER BY ... |> LIMIT 10
--
-- SQL reads in an order nobody writes in. You start typing SELECT, then jump
-- back to FROM, then to WHERE, then return to the select list once you know
-- what you are grouping by. Pipe syntax lets the text run in the order the
-- data flows, one operator at a time.
--
-- Every step is a complete query. You can cut the chain anywhere and run the
-- prefix, which is the practical reason to care: building a query becomes
-- append-only instead of edit-in-the-middle.

SELECT '════════ 1. The whole idea in one line ════════' AS section;

-- Classic
SELECT city, sum(n) AS total
FROM (SELECT arrayJoin([('seoul', 10), ('seoul', 5), ('busan', 7),
                        ('busan', 3), ('jeju', 1)]::Array(Tuple(String, UInt32))) AS t,
             t.1 AS city, t.2 AS n)
WHERE n > 2
GROUP BY city
ORDER BY total DESC;

-- The same thing, in the order it happens
CREATE OR REPLACE TABLE trips (city String, n UInt32) ENGINE = Memory;
INSERT INTO trips VALUES ('seoul', 10), ('seoul', 5), ('busan', 7), ('busan', 3), ('jeju', 1);

FROM trips
|> WHERE n > 2
|> AGGREGATE sum(n) AS total GROUP BY city
|> ORDER BY total DESC;

SELECT '════════ 2. Every operator, one at a time ════════' AS section;

-- The parser will list them if you ask it something it does not know:
--   WHERE, SELECT, EXTEND, SET, DROP, AS, AGGREGATE, DISTINCT,
--   ORDER BY, LIMIT, OFFSET, UNION, INTERSECT, EXCEPT, and the JOIN family.

SELECT '-- WHERE: filter, repeatable' AS step;
FROM trips |> WHERE n > 2 |> WHERE city != 'jeju' |> SELECT count() AS rows;

SELECT '-- SELECT: replaces the column list' AS step;
FROM trips |> SELECT city, n |> WHERE n = 10 |> SELECT city;

SELECT '-- EXTEND: add a column, keep the rest' AS step;
FROM trips |> EXTEND n * 2 AS doubled |> ORDER BY doubled DESC |> LIMIT 2;

SELECT '-- SET: overwrite a column in place' AS step;
FROM trips |> SET n = n + 100 |> ORDER BY n DESC |> LIMIT 2;

SELECT '-- DROP: remove a column' AS step;
FROM trips |> DROP city |> LIMIT 2;

SELECT '-- AGGREGATE: GROUP BY without leaving the pipe' AS step;
FROM trips |> AGGREGATE count() AS c, sum(n) AS total GROUP BY city |> ORDER BY city;

SELECT '-- DISTINCT' AS step;
FROM trips |> SELECT city |> DISTINCT |> ORDER BY city;

SELECT '-- ORDER BY / LIMIT / OFFSET' AS step;
FROM trips |> ORDER BY n DESC |> OFFSET 1 |> LIMIT 2;

SELECT '-- UNION between pipes' AS step;
FROM trips |> WHERE city = 'jeju' |> SELECT n
|> UNION ALL (SELECT 99 AS n);

SELECT '════════ 3. Why append-only matters ════════' AS section;

-- Each of these is a valid query on its own. Run the first, look at it, paste
-- the next line on the end. Nothing above ever has to be edited — which is the
-- difference between exploring data and rewriting a query five times.

FROM trips;
FROM trips |> WHERE n >= 5;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city;
FROM trips |> WHERE n >= 5 |> AGGREGATE sum(n) AS total GROUP BY city |> ORDER BY total DESC;

SELECT '════════ 4. It is the same query to the planner ════════' AS section;

-- Pipe syntax is parsed into the same AST as the classic form. It is sugar,
-- not a different execution path — so nothing about performance changes, and
-- EXPLAIN shows you the plan you already know how to read.

EXPLAIN SYNTAX
FROM trips |> WHERE n > 2 |> AGGREGATE sum(n) AS total GROUP BY city;

SELECT '════════ 5. Where it does not help ════════' AS section;

-- A single-table lookup is shorter in the classic form, and pretending
-- otherwise is how a good feature gets a bad reputation.
SELECT n FROM trips WHERE city = 'jeju';
FROM trips |> WHERE city = 'jeju' |> SELECT n;

-- Cleanup left commented so you can keep poking at the table.
-- DROP TABLE IF EXISTS trips;
