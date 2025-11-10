--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) Aggregation pushdown
SELECT
    channel,
    col_name,
    d_year,
    d_qoy,
    i_category,
    sum(sales_cnt) AS sales_cnt,
    sum(ext_sales_price) AS sales_amt
FROM
(
    SELECT
        'store' AS channel,
        'ss_cdemo_sk' AS col_name,
        ss_sold_date_sk AS date_sk,
        ss_item_sk AS item_sk,
        count() AS sales_cnt,
        sum(ss_ext_sales_price) AS ext_sales_price
    FROM store_sales
    WHERE ss_cdemo_sk IS NULL
    GROUP BY
        ss_sold_date_sk,
        ss_item_sk
    UNION ALL
    SELECT
        'web' AS channel,
        'ws_bill_customer_sk' AS col_name,
        ws_sold_date_sk AS date_sk,
        ws_item_sk AS item_sk,
        count() AS sales_cnt,
        sum(ws_ext_sales_price) AS ext_sales_price
    FROM web_sales
    WHERE ws_bill_customer_sk IS NULL
    GROUP BY
        ws_sold_date_sk,
        ws_item_sk
    UNION ALL
    SELECT
        'catalog' AS channel,
        'cs_warehouse_sk' AS col_name,
        cs_sold_date_sk AS date_sk,
        cs_item_sk AS item_sk,
        count() AS sales_cnt,
        sum(cs_ext_sales_price) AS ext_sales_price
    FROM catalog_sales
    WHERE cs_warehouse_sk IS NULL
    GROUP BY
        cs_sold_date_sk,
        cs_item_sk
) AS foo, item, date_dim
WHERE (date_sk = d_date_sk) AND (item_sk = i_item_sk)
GROUP BY
    channel,
    col_name,
    d_year,
    d_qoy,
    i_category
ORDER BY
    channel ASC,
    col_name ASC,
    d_year ASC,
    d_qoy ASC,
    i_category ASC
LIMIT 100