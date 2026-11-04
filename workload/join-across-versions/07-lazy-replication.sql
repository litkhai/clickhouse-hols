-- settings: enable_lazy_columns_replication
-- Many-to-many join (contacts has about 10 rows per customer_id, the facts subset about 2): the wide
-- note column is replicated for every match. Lazy replication avoids materialising the copies.

-- probe: 07-lazy-default repeat=2
-- No setting: each version's own default.
SELECT count() AS n, sum(cityHash64(c.note)) AS h
FROM join_lab.contacts AS c
INNER JOIN (SELECT customer_id, amount FROM join_lab.facts WHERE customer_id < 100000 AND id % 5 = 0) AS f
    ON c.customer_id = f.customer_id;

-- probe: 07-lazy-on repeat=2
SELECT count() AS n, sum(cityHash64(c.note)) AS h
FROM join_lab.contacts AS c
INNER JOIN (SELECT customer_id, amount FROM join_lab.facts WHERE customer_id < 100000 AND id % 5 = 0) AS f
    ON c.customer_id = f.customer_id
SETTINGS enable_lazy_columns_replication = 1;

-- probe: 07-lazy-off repeat=2
-- Negative: replication done eagerly.
SELECT count() AS n, sum(cityHash64(c.note)) AS h
FROM join_lab.contacts AS c
INNER JOIN (SELECT customer_id, amount FROM join_lab.facts WHERE customer_id < 100000 AND id % 5 = 0) AS f
    ON c.customer_id = f.customer_id
SETTINGS enable_lazy_columns_replication = 0;
