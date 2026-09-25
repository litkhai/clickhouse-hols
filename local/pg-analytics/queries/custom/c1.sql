-- L1 · C1 monthly row count over one quarter: partition pruning on month(l_shipdate)
SELECT date_trunc('month', l_shipdate) AS m, count(*) AS n
FROM lineitem
WHERE l_shipdate >= date '1996-01-01' AND l_shipdate < date '1996-04-01'
GROUP BY 1
ORDER BY 1;
