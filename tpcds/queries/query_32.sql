WITH 
subquery as (
SELECT cs_item_sk as subquery_item_sk, 1.3 * avg(cs_ext_discount_amt) as lim
FROM   catalog_sales
WHERE   
cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim where Cast(d_date AS DATE) BETWEEN Cast('2001-03-04' AS DATE) AND (Cast('2001-06-03' AS DATE)))
GROUP BY cs_item_sk
)
SELECT
       Sum(cs_ext_discount_amt) AS excess_discount_amount
FROM   catalog_sales,
       item,
       subquery
WHERE  i_manufact_id = 610
AND    i_item_sk = cs_item_sk
AND    cs_item_sk IN (SELECT i_item_sk from item where i_manufact_id = 610)
AND    cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE Cast(d_date AS DATE) BETWEEN Cast('2001-03-04' AS DATE) AND (Cast('2001-06-03' AS DATE)))
AND    cs_ext_discount_amt = subquery_item_sk
AND    cs_ext_discount_amt > lim 
LIMIT 100;