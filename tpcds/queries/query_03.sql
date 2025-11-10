--- 1) Filtering joins rewritten to where join key IN ...
SELECT
    dt.d_year,
    item.i_brand_id AS brand_id,
    item.i_brand AS brand,
    sum(ss_sales_price) AS sum_agg
FROM date_dim AS dt, store_sales, item
WHERE (dt.d_date_sk = store_sales.ss_sold_date_sk) AND (store_sales.ss_item_sk = item.i_item_sk) AND (item.i_manufact_id = 816) AND (dt.d_moy = 11)
    AND (store_sales.ss_item_sk IN (
    SELECT i_item_sk
    FROM item
    WHERE i_manufact_id = 816
)) AND (store_sales.ss_sold_date_sk IN (
    SELECT d_date_sk
    FROM date_dim
    WHERE d_moy = 11
))
GROUP BY
    dt.d_year,
    item.i_brand,
    item.i_brand_id
ORDER BY
    dt.d_year ASC,
    sum_agg DESC,
    brand_id ASC
LIMIT 100