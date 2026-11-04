-- settings: enable_join_runtime_filters, enable_join_runtime_filters_index_analysis
-- Runtime filters: values of the build side are pushed into the scan of the probe side.
-- Compare read_rows and memory with the setting on and off.

-- probe: 05-star-default events
-- The star join with no runtime-filter setting at all: shows each version's own default (and runs
-- on versions that do not know the setting).
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
INNER JOIN join_lab.regions AS r ON c.region = r.id
WHERE r.name = 'region-3';

-- probe: 05-star-on events
-- Star join facts -> customers -> regions with a selective filter on regions (1 of 20 regions).
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
INNER JOIN join_lab.regions AS r ON c.region = r.id
WHERE r.name = 'region-3'
SETTINGS enable_join_runtime_filters = 1;

-- probe: 05-star-off events
-- Negative: the same star join with runtime filters disabled.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN join_lab.customers AS c ON f.customer_id = c.id
INNER JOIN join_lab.regions AS r ON c.region = r.id
WHERE r.name = 'region-3'
SETTINGS enable_join_runtime_filters = 0;

-- probe: 05-direct-default events
-- The selective-build-side join with no runtime-filter setting.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN (SELECT id FROM join_lab.customers WHERE id % 1000 = 0) AS c ON f.customer_id = c.id;

-- probe: 05-direct-on events
-- A very selective build side (500 customers) joined directly to the facts.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN (SELECT id FROM join_lab.customers WHERE id % 1000 = 0) AS c ON f.customer_id = c.id
SETTINGS enable_join_runtime_filters = 1;

-- probe: 05-direct-off events
-- Negative: the same, runtime filters disabled.
SELECT count() AS n, sum(f.amount) AS total
FROM join_lab.facts AS f
INNER JOIN (SELECT id FROM join_lab.customers WHERE id % 1000 = 0) AS c ON f.customer_id = c.id
SETTINGS enable_join_runtime_filters = 0;
