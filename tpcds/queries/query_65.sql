--- 1) Filtering joins rewritten to where join key IN ...
SELECT
    s_store_name,
    i_item_desc,
    sc.revenue,
    i_current_price,
    i_wholesale_cost,
    i_brand
FROM store, item,
(
    SELECT
        ss_store_sk,
        avg(revenue) AS ave
    FROM
    (
        SELECT
            ss_store_sk,
            ss_item_sk,
            sum(ss_sales_price) AS revenue
        FROM store_sales
        WHERE ss_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_month_seq >= 1201) AND (d_month_seq <= (1201 + 11))
        )
        GROUP BY
            ss_store_sk,
            ss_item_sk
    ) AS sa
    GROUP BY ss_store_sk
) AS sb,
(
    SELECT
        ss_store_sk,
        ss_item_sk,
        sum(ss_sales_price) AS revenue
    FROM store_sales
    WHERE ss_sold_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE (d_month_seq >= 1201) AND (d_month_seq <= (1201 + 11))
    )
    GROUP BY
        ss_store_sk,
        ss_item_sk
) AS sc
WHERE (sb.ss_store_sk = sc.ss_store_sk) AND (sc.revenue <= (0.1 * sb.ave)) AND (s_store_sk = sc.ss_store_sk) AND (i_item_sk = sc.ss_item_sk)
ORDER BY
    s_store_name ASC,
    i_item_desc ASC
LIMIT 100