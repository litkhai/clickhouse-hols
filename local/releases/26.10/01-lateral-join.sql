-- ClickHouse 26.10 — LATERAL JOIN and joins on arbitrary ON conditions
--
--   LEFT JOIN LATERAL (SELECT ... WHERE inner.k = outer.k ORDER BY ... LIMIT n) AS t ON true
--   LEFT JOIN t ON <any boolean expression over both sides>
--
-- Two join changes that remove a class of "rewrite it first" queries.
--
-- LATERAL lets a subquery in FROM refer to the row on its left, which is the
-- standard spelling of "top n per group" and "an aggregate per row". It is
-- experimental (allow_experimental_lateral_join) and ClickHouse does not run it
-- row by row: it decorrelates the subquery into a LIMIT BY and a hash join,
-- which section 3 shows in the plan.
--
-- The block nested loop join is production. An OUTER join whose ON has no
-- equality between the two tables used to fail with INVALID_JOIN_ON_EXPRESSION;
-- it now runs, at the cost of comparing every left block with every right block.
--
-- The refusals (unsupported LATERAL forms, the old error with the new join
-- switched off) raise exceptions, so they live in 01-lateral-join.sh.

SELECT '════════ 1. Two small tables ════════' AS section;

DROP DATABASE IF EXISTS lj;
CREATE DATABASE lj;

CREATE TABLE lj.customers (id UInt32, name String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE lj.orders (id UInt32, customer_id UInt32, amount Decimal(10, 2), ts DateTime)
ENGINE = MergeTree ORDER BY (customer_id, ts);

-- Customer 3 has no orders on purpose: what a LATERAL join does with an empty
-- right side is half of what there is to learn here.
INSERT INTO lj.customers VALUES (1, 'acme'), (2, 'globex'), (3, 'initech');
INSERT INTO lj.orders
SELECT number, number % 2 + 1, (number * 7) % 100, toDateTime('2026-10-01 00:00:00') + number * 3600
FROM numbers(10);

SELECT customer_id, groupArray(toUInt32(amount)) AS amounts FROM lj.orders GROUP BY customer_id ORDER BY customer_id;

SELECT '════════ 2. Top 2 orders per customer ════════' AS section;

SET allow_experimental_lateral_join = 1;

-- The subquery refers to c.id, the row on its left. ON true is required: the
-- correlation lives inside the subquery, not in the join condition.
--
-- join_use_nulls = 1 is not optional in practice. With the default 0, the
-- customer without orders comes back with id 0 and amount 0.00, which reads like
-- a real order. Section 2b shows it.
SELECT c.name, t.id AS order_id, t.amount
FROM lj.customers AS c
LEFT JOIN LATERAL (
    SELECT id, amount FROM lj.orders AS o
    WHERE o.customer_id = c.id
    ORDER BY amount DESC
    LIMIT 2
) AS t ON true
ORDER BY c.name, t.amount DESC
SETTINGS join_use_nulls = 1;

SELECT '-- 2b. same query, join_use_nulls = 0 (the default): initech gets order 0' AS note;
SELECT c.name, t.id AS order_id, t.amount
FROM lj.customers AS c
LEFT JOIN LATERAL (
    SELECT id, amount FROM lj.orders AS o
    WHERE o.customer_id = c.id
    ORDER BY amount DESC
    LIMIT 2
) AS t ON true
WHERE c.name = 'initech';

SELECT '-- 2c. an aggregate per row: INNER keeps initech, because count() of nothing is still a row' AS note;
SELECT c.name, t.n, t.total
FROM lj.customers AS c
INNER JOIN LATERAL (
    SELECT count() AS n, sum(amount) AS total FROM lj.orders AS o
    WHERE o.customer_id = c.id
) AS t ON true
ORDER BY c.name;

SELECT '════════ 3. What it runs: a LIMIT BY and a hash join ════════' AS section;

-- The plan has no per-row loop. The correlated predicate became a join key
-- (cid <=> cid), and ORDER BY ... LIMIT 2 became LIMIT 2 BY customer_id, labelled
-- "LIMIT BY for decorrelated correlated subquery".
EXPLAIN
SELECT c.name, t.id
FROM lj.customers AS c
LEFT JOIN LATERAL (
    SELECT id, amount FROM lj.orders AS o
    WHERE o.customer_id = c.id
    ORDER BY amount DESC
    LIMIT 2
) AS t ON true;

-- Which means the hand-written version was always available, and returns the
-- same rows. LATERAL is the readable spelling, not a new capability.
SELECT '-- 3b. the hand-written equivalent: LIMIT 2 BY, then a plain join' AS note;
SELECT c.name, t.id AS order_id, t.amount
FROM lj.customers AS c
LEFT JOIN (
    SELECT customer_id, id, amount FROM lj.orders
    ORDER BY customer_id, amount DESC
    LIMIT 2 BY customer_id
) AS t ON t.customer_id = c.id
ORDER BY c.name, t.amount DESC
SETTINGS join_use_nulls = 1;

SELECT '════════ 4. OUTER joins on a condition with no equality ════════' AS section;

-- A price band table whose bands overlap (50-70 is both mid and high).
CREATE TABLE lj.bands (lo UInt32, hi UInt32, label String) ENGINE = Memory;
INSERT INTO lj.bands VALUES (0, 30, 'low'), (30, 70, 'mid'), (50, 100, 'high');

-- "The band whose lower edge is within 10 of the amount". No column of one side
-- equals a column of the other, so there is no hash key. Before 26.10 this
-- failed with INVALID_JOIN_ON_EXPRESSION (Code 403) — the .sh shows the same
-- error by switching the new join off.
SELECT o.id, o.amount, b.label
FROM lj.orders AS o
LEFT JOIN lj.bands AS b ON abs(toInt64(o.amount) - toInt64(b.lo)) < 10
ORDER BY o.id, b.label
SETTINGS join_use_nulls = 1;

SELECT '-- 4b. the plan names the new algorithm' AS note;
EXPLAIN PLAN actions = 0
SELECT o.id, b.label
FROM lj.orders AS o
LEFT JOIN lj.bands AS b ON abs(toInt64(o.amount) - toInt64(b.lo)) < 10;

SELECT '-- 4c. FULL works too: bands no order exceeds come back with NULL on the left' AS note;
SELECT o.id, b.label
FROM lj.orders AS o
FULL JOIN lj.bands AS b ON o.amount > b.hi
ORDER BY o.id, b.label
SETTINGS join_use_nulls = 1;

SELECT '════════ 5. Which join ran: the new query_log columns ════════' AS section;

-- INNER joins on such conditions already worked before 26.10, and still do not
-- use the new algorithm: a range becomes an IE_JOIN, anything else a CROSS JOIN
-- with a filter. Only OUTER joins needed something new.
SELECT count() FROM lj.orders AS o JOIN lj.bands AS b ON o.amount >= b.lo AND o.amount < b.hi
SETTINGS log_comment = 'lj_inner_range';
SELECT count() FROM lj.orders AS o JOIN lj.bands AS b ON abs(toInt64(o.amount) - toInt64(b.lo)) < 10
SETTINGS log_comment = 'lj_inner_func';
SELECT count() FROM lj.orders AS o LEFT JOIN lj.bands AS b ON abs(toInt64(o.amount) - toInt64(b.lo)) < 10
SETTINGS log_comment = 'lj_left_func';
SELECT count() FROM lj.orders AS o LEFT JOIN lj.customers AS c ON o.customer_id = c.id
SETTINGS log_comment = 'lj_left_equi';

SYSTEM FLUSH LOGS query_log;

-- used_join_algorithms, used_join_kinds, used_number_of_joins are new in 26.10.
-- The block nested loop row comes back empty with 0 joins on 26.10.3.7: the new
-- columns do not record the new algorithm. Find such queries by their EXPLAIN,
-- not by query_log, until that changes.
--
-- LIMIT 1 BY keeps the latest run of each query, so re-running the lab does not
-- pile up rows.
SELECT log_comment, used_join_algorithms, used_join_kinds, used_number_of_joins
FROM (
    SELECT * FROM system.query_log
    WHERE log_comment LIKE 'lj_%' AND type = 'QueryFinish'
    ORDER BY event_time_microseconds DESC
    LIMIT 1 BY log_comment
)
ORDER BY log_comment;
