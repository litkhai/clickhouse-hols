-- L2 · C3 distinct parts shipped per month: COUNT(DISTINCT) over the whole fact table
SELECT date_trunc('month', l_shipdate) AS m, count(DISTINCT l_partkey) AS parts
FROM lineitem
GROUP BY 1
ORDER BY 1;
