-- settings: join_algorithm, query_plan_join_swap_table, enable_join_runtime_filters, enable_lazy_columns_replication
-- Ten times the data of 00-data.sql, so that time differences between versions are larger than noise.
-- Uses facts_big, customers_big and contacts_big from 00-data.sql.

-- probe: 10-big-left repeat=5
-- (a) 50M-row fact table on the left, 5M-row dimension on the right, aggregated.
SELECT count() AS rows, sum(f.amount) AS total, uniqExact(c.region) AS regions
FROM join_lab.facts_big AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id;

-- probe: 10-big-right repeat=5
-- (b) the same join with the big table written on the right.
SELECT count() AS rows, sum(f.amount) AS total, uniqExact(c.region) AS regions
FROM join_lab.customers_big AS c
INNER JOIN join_lab.facts_big AS f ON f.customer_id = c.id;

-- probe: 10-star repeat=5 events
-- (c) star join facts_big -> customers_big -> regions with a selective filter on regions (1 of 20).
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts_big AS f
INNER JOIN join_lab.customers_big AS c ON f.customer_id = c.id
INNER JOIN join_lab.regions AS r ON c.region = r.id
WHERE r.name = 'region-3';

-- probe: 10-many-to-many-wide repeat=5
-- (d) many-to-many with the wide note column (about 5 contacts per customer_id, matched against the 10M-row facts subset of those customers).
SELECT count() AS n, sum(cityHash64(c.note)) AS h
FROM join_lab.contacts_big AS c
INNER JOIN (SELECT customer_id, amount FROM join_lab.facts_big WHERE customer_id < 1000000) AS f
    ON c.customer_id = f.customer_id;

-- probe: 10-many-to-many-wide-lazy-off repeat=5
-- (d) again with enable_lazy_columns_replication = 0: is lazy replication the cause of the time on 26.8 and 26.10?
SELECT count() AS n, sum(cityHash64(c.note)) AS h
FROM join_lab.contacts_big AS c
INNER JOIN (SELECT customer_id, amount FROM join_lab.facts_big WHERE customer_id < 1000000) AS f
    ON c.customer_id = f.customer_id
SETTINGS enable_lazy_columns_replication = 0;

-- probe: 10-codec-columns value
-- The codec the big tables' columns are stored with (00-data.sql pins CODEC(LZ4) on every column).
SELECT groupUniqArray(compression_codec) AS column_codecs, count() AS columns
FROM system.columns
WHERE database = 'join_lab' AND table IN ('facts_big', 'customers_big', 'contacts_big');

-- probe: 10-codec-parts value
-- The parts' own default codec and the largest part after the timed probes above. A part's default codec
-- applies only to columns without an explicit CODEC, so with the pin it does not change what was read.
SELECT groupUniqArray(default_compression_codec) AS part_default_codecs, count() AS parts, max(bytes_on_disk) AS max_part_bytes
FROM system.parts
WHERE database = 'join_lab' AND table IN ('facts_big', 'customers_big', 'contacts_big') AND active;
