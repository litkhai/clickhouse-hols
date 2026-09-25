-- L5 · C5 last 12 months of revenue by month: crosses the hot/cold cutoff (1998-02-01)
SELECT date_trunc('month', o_orderdate) AS m, sum(o_totalprice) AS revenue, count(*) AS n
FROM orders_all
WHERE o_orderdate >= date '1997-08-01'
GROUP BY 1
ORDER BY 1;
