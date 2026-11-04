-- settings: join_use_nulls, allow_experimental_lateral_join
-- One tiny probe per join syntax. The matrix shows from which version each one parses.

-- probe: 08-asof-left
SELECT count() AS n, sum(p.price) AS total
FROM (SELECT customer_id, ts FROM join_lab.facts WHERE id < 1000000 AND customer_id < 2000) AS f
ASOF LEFT JOIN join_lab.prices AS p ON f.customer_id = p.customer_id AND f.ts >= p.ts;

-- probe: 08-left-semi
SELECT count() AS n FROM join_lab.regions AS r LEFT SEMI JOIN join_lab.customers AS c ON r.id = c.region;

-- probe: 08-left-anti
SELECT count() AS n FROM join_lab.regions AS r LEFT ANTI JOIN (SELECT region FROM join_lab.customers WHERE region < 10) AS c ON r.id = c.region;

-- probe: 08-paste
SELECT count() AS n, sum(a.x + b.y) AS total
FROM (SELECT number AS x FROM numbers(5)) AS a
PASTE JOIN (SELECT number * 10 AS y FROM numbers(5)) AS b;

-- probe: 08-natural
SELECT count() AS n
FROM (SELECT number AS id, number * 2 AS a FROM numbers(5)) AS l
NATURAL JOIN (SELECT number AS id, number * 3 AS b FROM numbers(5)) AS r;

-- probe: 08-using
SELECT count() AS n
FROM (SELECT number AS id FROM numbers(5)) AS l
INNER JOIN (SELECT number AS id FROM numbers(3)) AS r USING (id);

-- probe: 08-full-join-use-nulls
SELECT count() AS n, countIf(l.id IS NULL) AS left_nulls, countIf(r.id IS NULL) AS right_nulls
FROM (SELECT number AS id FROM numbers(5)) AS l
FULL JOIN (SELECT number + 3 AS id FROM numbers(5)) AS r ON l.id = r.id
SETTINGS join_use_nulls = 1;

-- probe: 08-lateral-left
SELECT count() AS n, sum(l.id) AS total
FROM join_lab.regions AS r
LEFT JOIN LATERAL (SELECT c.id FROM join_lab.customers AS c WHERE c.region = r.id ORDER BY c.id LIMIT 2) AS l ON true
SETTINGS allow_experimental_lateral_join = 1;
