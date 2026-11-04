-- settings: query_plan_join_swap_table, join_algorithm
-- The same join written with the big table on the RIGHT (the build side of a hash join).
-- Does the server swap the sides and build the hash table from the small table?

-- probe: 02-big-left-control repeat=2
-- Control: big table on the left.
SELECT count() AS rows, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'hash';

-- probe: 02-big-right-default repeat=2
-- Positive: big table on the right, default swap behaviour. Peak memory shows whether it was swapped.
SELECT count() AS rows, sum(f.amount) AS total
FROM join_lab.customers AS c
INNER JOIN join_lab.facts AS f ON f.customer_id = c.id
SETTINGS join_algorithm = 'hash';

-- probe: 02-big-right-no-swap repeat=2
-- Negative: swapping disabled with query_plan_join_swap_table = 'false'. Expect the 5M-row table in memory.
SELECT count() AS rows, sum(f.amount) AS total
FROM join_lab.customers AS c
INNER JOIN join_lab.facts AS f ON f.customer_id = c.id
SETTINGS join_algorithm = 'hash', query_plan_join_swap_table = 'false';
