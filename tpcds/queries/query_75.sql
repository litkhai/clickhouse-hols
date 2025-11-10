--- 1) UNION default behaviour is not set to DISTINCT
--- 2) FIXED 0. to 0 as 0. parsed as float and did not convert to Decimal. https://github.com/ClickHouse/ClickHouse/issues/5690
--- 3) Filtering joins rewritten to where join key IN ...
--- 4) Take possible values for filter from external select and prefilter
--- 5) Joins that do not participate in aggregation are moved to upper level
WITH all_sales AS
    (
        SELECT
            d_year,
            i_brand_id,
            i_class_id,
            i_category_id,
            i_manufact_id,
            SUM(sales_cnt) AS sales_cnt,
            SUM(sales_amt) AS sales_amt
        FROM
        (
            SELECT
                cs_sold_date_sk AS date_sk,
                cs_item_sk AS item_sk,
                cs_quantity - COALESCE(cr_return_quantity, 0) AS sales_cnt,
                cs_ext_sales_price - COALESCE(cr_return_amount, CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
            FROM catalog_sales
            LEFT JOIN catalog_returns ON (cs_order_number = cr_order_number) AND (cs_item_sk = cr_item_sk)
            WHERE (cs_item_sk IN (
                SELECT i_item_sk
                FROM item
                WHERE i_category = 'Electronics'
            )) AND (cs_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 2002) OR (d_year = (2002 - 1))
            ))
            UNION
            SELECT
                ss_sold_date_sk AS date_sk,
                ss_item_sk AS item_sk,
                ss_quantity - COALESCE(sr_return_quantity, 0) AS sales_cnt,
                ss_ext_sales_price - COALESCE(sr_return_amt, CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
            FROM store_sales
            LEFT JOIN store_returns ON (ss_ticket_number = sr_ticket_number) AND (ss_item_sk = sr_item_sk)
            WHERE (ss_item_sk IN (
                SELECT i_item_sk
                FROM item
                WHERE i_category = 'Electronics'
            )) AND (ss_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 2002) OR (d_year = (2002 - 1))
            ))
            UNION
            SELECT
                ws_ext_sales_price AS date_sk,
                ws_item_sk AS item_sk,
                ws_quantity - COALESCE(wr_return_quantity, 0) AS sales_cnt,
                ws_ext_sales_price - COALESCE(wr_return_amt, CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
            FROM web_sales
            LEFT JOIN web_returns ON (ws_order_number = wr_order_number) AND (ws_item_sk = wr_item_sk)
            WHERE (ws_item_sk IN (
                SELECT i_item_sk
                FROM item
                WHERE i_category = 'Electronics'
            )) AND (ws_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 2002) OR (d_year = (2002 - 1))
            ))
        ) AS sales_detail, item, date_dim
        WHERE (i_item_sk = item_sk) AND (d_date_sk = date_sk)
        GROUP BY
            d_year,
            i_brand_id,
            i_class_id,
            i_category_id,
            i_manufact_id
    )
SELECT
    prev_yr.d_year AS prev_year,
    curr_yr.d_year AS year,
    curr_yr.i_brand_id,
    curr_yr.i_class_id,
    curr_yr.i_category_id,
    curr_yr.i_manufact_id,
    prev_yr.sales_cnt AS prev_yr_cnt,
    curr_yr.sales_cnt AS curr_yr_cnt,
    curr_yr.sales_cnt - prev_yr.sales_cnt AS sales_cnt_diff,
    curr_yr.sales_amt - prev_yr.sales_amt AS sales_amt_diff
FROM all_sales AS curr_yr, all_sales AS prev_yr
WHERE (curr_yr.i_brand_id = prev_yr.i_brand_id) AND (curr_yr.i_class_id = prev_yr.i_class_id) AND (curr_yr.i_category_id = prev_yr.i_category_id) AND (curr_yr.i_manufact_id = prev_yr.i_manufact_id) AND (curr_yr.d_year = 2002) AND (prev_yr.d_year = (2002 - 1)) AND ((CAST(curr_yr.sales_cnt, 'DECIMAL(17, 2)') / CAST(prev_yr.sales_cnt, 'DECIMAL(17, 2)')) < CAST('0.9', 'Decimal(7, 2)'))
ORDER BY
    sales_cnt_diff ASC,
    sales_amt_diff ASC
LIMIT 100
SETTINGS union_default_mode = 'DISTINCT';


-- WITH 
--   all_sales AS (
--     SELECT
--       d_year
--       ,i_brand_id
--       ,i_class_id
--       ,i_category_id
--       ,i_manufact_id
--       ,SUM(sales_cnt) AS sales_cnt
--       ,SUM(sales_amt) AS sales_amt
--     FROM 
--     (
--       SELECT 
--         d_year
--         ,i_brand_id
--         ,i_class_id
--         ,i_category_id
--         ,i_manufact_id
--         ,cs_quantity - COALESCE(cr_return_quantity,0) AS sales_cnt
--         ,cs_ext_sales_price - COALESCE(cr_return_amount,CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
--       FROM 
--         catalog_sales 
--         JOIN item ON i_item_sk=cs_item_sk
--         JOIN date_dim ON d_date_sk=cs_sold_date_sk
--         LEFT JOIN catalog_returns ON (
--           cs_order_number=cr_order_number 
--           AND cs_item_sk=cr_item_sk)
--       WHERE 
--         i_category='Electronics'
--         and cs_item_sk in (select i_item_sk from item where i_category='Electronics')
--         and cs_sold_date_sk in (select d_date_sk from date_dim where d_year = 2002 or d_year = 2002-1)
--       UNION

--       SELECT
--         d_year
--         ,i_brand_id
--         ,i_class_id
--         ,i_category_id
--         ,i_manufact_id
--         ,ss_quantity - COALESCE(sr_return_quantity,0) AS sales_cnt
--         ,ss_ext_sales_price - COALESCE(sr_return_amt,CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
--       FROM 
--         store_sales 
--         JOIN item ON i_item_sk=ss_item_sk
--         JOIN date_dim ON d_date_sk=ss_sold_date_sk
--         LEFT JOIN store_returns ON (
--           ss_ticket_number=sr_ticket_number 
--           AND ss_item_sk=sr_item_sk)
--       WHERE 
--         i_category='Electronics'
--         and ss_item_sk in (select i_item_sk from item where i_category='Electronics')
--         and ss_sold_date_sk in (select d_date_sk from date_dim where d_year = 2002 or d_year = 2002-1)

--       UNION

--       SELECT 
--         d_year
--         ,i_brand_id
--         ,i_class_id
--         ,i_category_id
--         ,i_manufact_id
--         ,ws_quantity - COALESCE(wr_return_quantity,0) AS sales_cnt
--         ,ws_ext_sales_price - COALESCE(wr_return_amt,CAST('0.0', 'Decimal(7, 2)')) AS sales_amt
--       FROM 
--         web_sales 
--         JOIN item ON i_item_sk=ws_item_sk
--         JOIN date_dim ON d_date_sk=ws_sold_date_sk
--         LEFT JOIN web_returns ON (
--           ws_order_number=wr_order_number 
--           AND ws_item_sk=wr_item_sk)
--       WHERE 
--         i_category='Electronics'
--         and ws_item_sk in (select i_item_sk from item where i_category='Electronics')
--         and ws_sold_date_sk in (select d_date_sk from date_dim where d_year = 2002 or d_year = 2002-1)
--     ) sales_detail
--     GROUP BY 
--       d_year,
--       i_brand_id,
--       i_class_id,
--       i_category_id,
--       i_manufact_id
--   )
-- SELECT 
--   prev_yr.d_year AS prev_year
--   ,curr_yr.d_year AS year
--   ,curr_yr.i_brand_id
--   ,curr_yr.i_class_id
--   ,curr_yr.i_category_id
--   ,curr_yr.i_manufact_id
--   ,prev_yr.sales_cnt AS prev_yr_cnt
--   ,curr_yr.sales_cnt AS curr_yr_cnt
--   ,curr_yr.sales_cnt-prev_yr.sales_cnt AS sales_cnt_diff
--   ,curr_yr.sales_amt-prev_yr.sales_amt AS sales_amt_diff
-- FROM 
--   all_sales curr_yr,
--   all_sales prev_yr
-- WHERE 
--   curr_yr.i_brand_id=prev_yr.i_brand_id
--   AND curr_yr.i_class_id=prev_yr.i_class_id
--   AND curr_yr.i_category_id=prev_yr.i_category_id
--   AND curr_yr.i_manufact_id=prev_yr.i_manufact_id
--   AND curr_yr.d_year=2002
--   AND prev_yr.d_year=2002-1
--   AND CAST(curr_yr.sales_cnt AS DECIMAL(17,2))/CAST(prev_yr.sales_cnt AS DECIMAL(17,2))<CAST('0.9', 'Decimal(7, 2)')
-- ORDER BY 
--   sales_cnt_diff,
--   sales_amt_diff
-- LIMIT 100
-- SETTINGS union_default_mode = 'DISTINCT';

