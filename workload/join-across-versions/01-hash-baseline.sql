-- settings: join_algorithm
-- Baseline: a 5M-row fact table joined to a 500k-row dimension, aggregated. The big table is on the
-- left, which is the layout every version handles well. Only the join_algorithm default changes.

-- probe: 01-default repeat=3
-- Positive: whatever the version's default join_algorithm picks.
SELECT count() AS rows, sum(f.amount) AS total, uniqExact(c.region) AS regions
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id;

-- probe: 01-hash repeat=3
-- Same join forced onto the single-threaded-build hash algorithm.
SELECT count() AS rows, sum(f.amount) AS total, uniqExact(c.region) AS regions
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'hash';

-- probe: 01-parallel-hash repeat=3
-- Same join forced onto the parallel hash algorithm.
SELECT count() AS rows, sum(f.amount) AS total, uniqExact(c.region) AS regions
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'parallel_hash';
