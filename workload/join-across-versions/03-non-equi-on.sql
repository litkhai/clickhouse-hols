-- settings: join_algorithm, allow_experimental_join_condition, allow_block_nested_loop_join
-- JOIN ... ON with conditions that are not plain equalities. Where the join is nested-loop shaped the
-- left side is limited to 100k facts, so the matrix stays fast.

-- probe: 03-range-inner show
-- INNER, range condition against a 100-row table.
SELECT b.lo, count() AS n
FROM (SELECT amount FROM join_lab.facts WHERE id < 100000) AS f
INNER JOIN join_lab.bands AS b ON f.amount >= b.lo AND f.amount < b.hi
GROUP BY b.lo ORDER BY b.lo LIMIT 5;

-- probe: 03-arbitrary-inner
-- INNER, arbitrary expression on both sides.
SELECT count() AS n
FROM (SELECT amount FROM join_lab.facts WHERE id < 100000) AS f
INNER JOIN join_lab.bands AS b ON abs(f.amount - b.lo) < 10;

-- probe: 03-arbitrary-left
-- LEFT, the same arbitrary expression (the 26.10 lab saw Code 403 on 26.9.11.2).
SELECT count() AS n, countIf(b.hi = 0) AS unmatched
FROM (SELECT amount FROM join_lab.facts WHERE id < 100000) AS f
LEFT JOIN join_lab.bands AS b ON abs(f.amount - b.lo) < 10;

-- probe: 03-arbitrary-left-flag
-- Control: the same LEFT join with the flag older servers needed (obsolete, ignored on new ones).
SELECT count() AS n, countIf(b.hi = 0) AS unmatched
FROM (SELECT amount FROM join_lab.facts WHERE id < 100000) AS f
LEFT JOIN join_lab.bands AS b ON abs(f.amount - b.lo) < 10
SETTINGS allow_experimental_join_condition = 1;

-- probe: 03-equi-ineq-inner
-- INNER, equality plus inequality: a hash join with a residual condition.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id AND f.amount > c.credit_limit;

-- probe: 03-equi-ineq-inner-flag
-- Control: the same with the flag older servers needed.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id AND f.amount > c.credit_limit
SETTINGS allow_experimental_join_condition = 1;

-- probe: 03-equi-ineq-left
-- LEFT, equality plus inequality.
SELECT count() AS n, countIf(c.credit_limit = 0) AS no_match_or_zero
FROM join_lab.facts AS f
LEFT JOIN join_lab.customers AS c ON f.customer_id = c.id AND f.amount > c.credit_limit;
