-- settings: enable_join_runtime_filters, allow_experimental_lateral_join
-- EXPLAIN of three joins from the earlier files. The full text is stored in results/*.json and the
-- newest version's plan is printed in RESULTS.md.

-- probe: 09-explain-runtime-filter show
EXPLAIN actions = 1
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
INNER JOIN join_lab.regions AS r ON c.region = r.id
WHERE r.name = 'region-3'
SETTINGS enable_join_runtime_filters = 1;

-- probe: 09-explain-lateral show
EXPLAIN actions = 1
SELECT count() AS n, sum(l.id) AS total
FROM join_lab.regions AS r
LEFT JOIN LATERAL (SELECT c.id FROM join_lab.customers AS c WHERE c.region = r.id ORDER BY c.id LIMIT 2) AS l ON true
SETTINGS allow_experimental_lateral_join = 1;

-- probe: 09-explain-left-arbitrary show
EXPLAIN actions = 1
SELECT count() AS n, countIf(b.hi = 0) AS unmatched
FROM (SELECT amount FROM join_lab.facts WHERE id < 100000) AS f
LEFT JOIN join_lab.bands AS b ON abs(f.amount - b.lo) < 10;
