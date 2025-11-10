--- 1) Filtering joins rewritten to where join key IN ...
SELECT *
FROM
(
    SELECT
        i_category,
        i_class,
        i_brand,
        i_product_name,
        d_year,
        d_qoy,
        d_moy,
        s_store_id,
        sumsales,
        rank() OVER (PARTITION BY i_category ORDER BY sumsales DESC) AS rk
    FROM
    (
        SELECT
            i_category,
            i_class,
            i_brand,
            i_product_name,
            d_year,
            d_qoy,
            d_moy,
            s_store_id,
            sum(coalesce(ss_sales_price * ss_quantity, 0)) AS sumsales
        FROM store_sales, date_dim, store, item
        WHERE (ss_sold_date_sk = d_date_sk) AND (ss_item_sk = i_item_sk) AND (ss_store_sk = s_store_sk) AND ((d_month_seq >= 1220) AND (d_month_seq <= (1220 + 11)))
        and ss_sold_date_sk IN (select d_date_sk from date_dim WHERE ((d_month_seq >= 1220) AND (d_month_seq <= (1220 + 11))))
        GROUP BY
            i_category,
            i_class,
            i_brand,
            i_product_name,
            d_year,
            d_qoy,
            d_moy,
            s_store_id
            WITH ROLLUP
    ) AS dw1
) AS dw2
WHERE rk <= 100
ORDER BY
    i_category ASC,
    i_class ASC,
    i_brand ASC,
    i_product_name ASC,
    d_year ASC,
    d_qoy ASC,
    d_moy ASC,
    s_store_id ASC,
    sumsales ASC,
    rk ASC
LIMIT 100