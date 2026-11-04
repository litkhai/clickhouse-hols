-- settings: join_algorithm, max_bytes_before_external_join, max_bytes_ratio_before_external_join, grace_hash_join_initial_buckets
-- The same join and the same 800 MB cap as ../06-memory-cap.sql, without a spill threshold or grace
-- buckets: the uncapped peaks in 06 are 1.3 to 2.4 times the cap, so these are expected to fail with
-- Code 241 (MEMORY_LIMIT_EXCEEDED). They fail on 26.10 itself, so tools/hol does not run this file.

-- probe: e01-default-capped events
-- The default join_algorithm under the cap, nothing else set.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000;

-- probe: e01-default-ratio-explicit events
-- The same with max_bytes_ratio_before_external_join written out at its default value (0.5), where it exists.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, max_bytes_ratio_before_external_join = 0.5;

-- probe: e01-hash-capped events
-- join_algorithm = 'hash' under the cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, join_algorithm = 'hash';

-- probe: e01-partial-merge-capped events
-- join_algorithm = 'partial_merge' under the cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, join_algorithm = 'partial_merge';

-- probe: e01-grace-hash-1-bucket-capped events
-- grace_hash with the default grace_hash_join_initial_buckets (1) under the cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, join_algorithm = 'grace_hash';
