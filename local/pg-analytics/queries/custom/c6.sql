-- L5 · C6 one order and its lines, looked up by key in cold storage (point lookup)
SELECT o_orderkey, o_custkey, o_orderstatus, o_totalprice, o_orderdate,
       l_linenumber, l_partkey, l_quantity, l_extendedprice
FROM orders_all
JOIN lineitem_all ON l_orderkey = o_orderkey
WHERE o_orderkey = 1000000
ORDER BY l_linenumber;
