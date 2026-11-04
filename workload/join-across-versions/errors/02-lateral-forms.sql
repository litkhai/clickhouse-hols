-- settings: allow_experimental_lateral_join
-- LATERAL forms other than `LEFT JOIN LATERAL (...) ON true` (that one is ../08-syntax.sql).
-- Each fails on 26.10 itself, so tools/hol does not run this file; the matrix records the outcome per version.

-- probe: e02-lateral-comma
-- Comma form: FROM a, LATERAL (...)
SELECT count() AS n
FROM join_lab.regions AS r, LATERAL (SELECT c.id FROM join_lab.customers AS c WHERE c.region = r.id LIMIT 2) AS l
SETTINGS allow_experimental_lateral_join = 1;

-- probe: e02-lateral-cross-join
SELECT count() AS n
FROM join_lab.regions AS r
CROSS JOIN LATERAL (SELECT c.id FROM join_lab.customers AS c WHERE c.region = r.id LIMIT 2) AS l
SETTINGS allow_experimental_lateral_join = 1;

-- probe: e02-lateral-uncorrelated
-- LATERAL subquery that does not reference the left side.
SELECT count() AS n
FROM join_lab.regions AS r
LEFT JOIN LATERAL (SELECT c.id FROM join_lab.customers AS c ORDER BY c.id LIMIT 2) AS l ON true
SETTINGS allow_experimental_lateral_join = 1;

-- probe: e02-lateral-with-ties
-- LIMIT ... WITH TIES inside the LATERAL subquery.
SELECT count() AS n
FROM join_lab.regions AS r
LEFT JOIN LATERAL (SELECT c.id FROM join_lab.customers AS c WHERE c.region = r.id ORDER BY c.credit_limit LIMIT 2 WITH TIES) AS l ON true
SETTINGS allow_experimental_lateral_join = 1;
