-- L2 · C2 top 100 customers by order revenue: high-cardinality GROUP BY + Top-N
SELECT o_custkey, sum(o_totalprice) AS revenue, count(*) AS n_orders
FROM orders
GROUP BY o_custkey
ORDER BY revenue DESC, o_custkey
LIMIT 100;
