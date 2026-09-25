-- L4 · C4 top-3 customers inside each month of 1997: window over an aggregate
SELECT m, o_custkey, revenue, rnk
FROM (SELECT date_trunc('month', o_orderdate) AS m,
             o_custkey,
             sum(o_totalprice) AS revenue,
             rank() OVER (PARTITION BY date_trunc('month', o_orderdate)
                          ORDER BY sum(o_totalprice) DESC) AS rnk
      FROM orders
      WHERE o_orderdate >= date '1997-01-01' AND o_orderdate < date '1998-01-01'
      GROUP BY 1, 2) AS t
WHERE rnk <= 3
ORDER BY m, rnk, o_custkey;
