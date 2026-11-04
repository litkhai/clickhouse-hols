-- settings: join_algorithm, max_bytes_before_external_join, max_bytes_ratio_before_external_join, grace_hash_join_initial_buckets
-- A join whose build side (5M customers_big rows with a ~200 byte comment, about 1.5 GB as a hash table) is far
-- larger than a 800 MB max_memory_usage cap. The probe side is the 5M-row facts table.
-- The uncapped probes give the peak memory of each algorithm; the capped probes below are the ones
-- that finish with a wide margin (the spilling paths). The paths that do not spill and fail with
-- Code 241 on 26.10 are in errors/01-memory-cap-defaults.sql, because tools/hol must not raise.
-- Spilling shows in the ProfileEvents (External*, JoinSpilling*).

-- probe: 06-uncapped events
-- Reference: the default algorithm, no cap. This peak is what the cap is compared with.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id;

-- probe: 06-uncapped-hash events
-- Reference: join_algorithm = 'hash', no cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'hash';

-- probe: 06-uncapped-partial-merge events
-- Reference: join_algorithm = 'partial_merge', no cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'partial_merge';

-- probe: 06-uncapped-grace-hash events
-- Reference: join_algorithm = 'grace_hash' (one bucket), no cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS join_algorithm = 'grace_hash';

-- probe: 06-grace-hash-8-buckets-capped events
-- grace_hash starting with 8 buckets under the cap: the build side is partitioned and spilled.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, join_algorithm = 'grace_hash', grace_hash_join_initial_buckets = 8;

-- probe: 06-grace-hash-16-buckets-capped events
-- grace_hash starting with 16 buckets under the cap.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, join_algorithm = 'grace_hash', grace_hash_join_initial_buckets = 16;

-- probe: 06-default-spill-capped events
-- The default algorithm list with an explicit spill threshold of 200 MB for the hash join.
SELECT count() AS n, sum(cityHash64(c.comment)) AS h
FROM join_lab.facts AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
SETTINGS max_memory_usage = 800000000, max_bytes_before_external_join = 200000000;
