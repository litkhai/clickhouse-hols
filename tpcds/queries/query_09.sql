--- 1) Preaggregate data before applying congitions - fuze subqueries with similar aggregation
WITH
    data AS
    (
        SELECT
            1+intDiv(ss_quantity-1, 20) AS bucket,
            count(*) AS c,
            avg(ss_ext_discount_amt) AS a1,
            avg(ss_net_paid) AS a2
        FROM store_sales
        GROUP BY bucket
    )
SELECT
    maxIf(if(c > 2972190, a1, a2), bucket = 1) as bucket1,
    maxIf(if(c > 4505785, a1, a2), bucket = 2) as bucket2,
    maxIf(if(c > 7797278, a1, a2), bucket = 3) as bucket3,
    maxIf(if(c > 16112224, a1, a2), bucket = 4) as bucket4,
    maxIf(if(c > 25211875, a1, a2), bucket = 5) as bucket5
FROM data
