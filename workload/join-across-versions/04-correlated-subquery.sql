-- settings: allow_correlated_subqueries, allow_experimental_correlated_subqueries, correlated_subqueries_substitute_equivalent_expressions
-- Correlated subqueries: the inner query refers to a column of the outer query.

-- probe: 04-exists show
-- EXISTS in the shape of TPC-H Q4: customers per region that have a large fact row.
SELECT c.region, count() AS n
FROM join_lab.customers AS c
WHERE EXISTS (SELECT 1 FROM join_lab.facts AS f WHERE f.customer_id = c.id AND f.amount > 9990)
GROUP BY c.region ORDER BY c.region LIMIT 5;

-- probe: 04-exists-no-substitution
-- The same, with the replacement of equivalent expressions switched off.
SELECT c.region, count() AS n
FROM join_lab.customers AS c
WHERE EXISTS (SELECT 1 FROM join_lab.facts AS f WHERE f.customer_id = c.id AND f.amount > 9990)
GROUP BY c.region ORDER BY c.region LIMIT 5
SETTINGS correlated_subqueries_substitute_equivalent_expressions = 0;

-- probe: 04-not-exists
-- NOT EXISTS: customers without any large fact row.
SELECT count() AS n
FROM join_lab.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM join_lab.facts AS f WHERE f.customer_id = c.id AND f.amount > 9990);

-- probe: 04-scalar-select-list show
-- Correlated scalar subquery in the select list, for 1000 customers.
SELECT count() AS n, sum(mx) AS total
FROM
(
    SELECT c.id, (SELECT max(f.amount) FROM join_lab.facts AS f WHERE f.customer_id = c.id) AS mx
    FROM join_lab.customers AS c
    WHERE c.id < 1000
);
