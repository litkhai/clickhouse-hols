--- 1) Parallel hash is crucial for LEFT OUTER JOIN
--- 2) Filtering joins rewritten to where join key IN ...
--- 3) It helped also to preaggregate data before join where possible. Grouping was made by future join on column
WITH
    ssr AS
    (
        SELECT
            s_store_id,
            sum(sales_price) AS sales,
            sum(profit) AS profit,
            sum(return_amt) AS returns,
            sum(net_loss) AS profit_loss
        FROM
        (
            SELECT
                ss_store_sk AS store_sk,
                sum(ss_ext_sales_price) AS sales_price,
                sum(ss_net_profit) AS profit,
                sum(CAST(0, 'decimal(7, 2)')) AS return_amt,
                sum(CAST(0, 'decimal(7, 2)')) AS net_loss
            FROM store_sales
            WHERE ss_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY ss_store_sk
            UNION ALL
            SELECT
                sr_store_sk AS store_sk,
                sum(CAST(0, 'decimal(7, 2)')) AS sales_price,
                sum(CAST(0, 'decimal(7, 2)')) AS profit,
                sum(sr_return_amt) AS return_amt,
                sum(sr_net_loss) AS net_loss
            FROM store_returns
            WHERE sr_returned_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY sr_store_sk
        ) AS salesreturns, store
        WHERE store_sk = s_store_sk
        GROUP BY s_store_id
    ),
    csr AS
    (
        SELECT
            cp_catalog_page_id,
            sum(sales_price) AS sales,
            sum(profit) AS profit,
            sum(return_amt) AS returns,
            sum(net_loss) AS profit_loss
        FROM
        (
            SELECT
                cs_catalog_page_sk AS page_sk,
                sum(cs_ext_sales_price) AS sales_price,
                sum(cs_net_profit) AS profit,
                sum(CAST(0, 'decimal(7, 2)')) AS return_amt,
                sum(CAST(0, 'decimal(7, 2)')) AS net_loss
            FROM catalog_sales
            WHERE cs_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY cs_catalog_page_sk
            UNION ALL
            SELECT
                cr_catalog_page_sk AS page_sk,
                sum(CAST(0, 'decimal(7, 2)')) AS sales_price,
                sum(CAST(0, 'decimal(7, 2)')) AS profit,
                sum(cr_return_amount) AS return_amt,
                sum(cr_net_loss) AS net_loss
            FROM catalog_returns
            WHERE cr_returned_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY cr_catalog_page_sk
        ) AS salesreturns, catalog_page
        WHERE page_sk = cp_catalog_page_sk
        GROUP BY cp_catalog_page_id
    ),
    wsr AS
    (
        SELECT
            web_site_id,
            sum(sales_price) AS sales,
            sum(profit) AS profit,
            sum(return_amt) AS returns,
            sum(net_loss) AS profit_loss
        FROM
        (
            SELECT
                ws_web_site_sk AS wsr_web_site_sk,
                sum(ws_ext_sales_price) AS sales_price,
                sum(ws_net_profit) AS profit,
                sum(CAST(0, 'decimal(7, 2)')) AS return_amt,
                sum(CAST(0, 'decimal(7, 2)')) AS net_loss
            FROM web_sales
            WHERE ws_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY ws_web_site_sk
            UNION ALL
            SELECT
                ws_web_site_sk AS wsr_web_site_sk,
                sum(CAST(0, 'decimal(7, 2)')) AS sales_price,
                sum(CAST(0, 'decimal(7, 2)')) AS profit,
                sum(wr_return_amt) AS return_amt,
                sum(wr_net_loss) AS net_loss
            FROM web_returns
            LEFT JOIN
            (
                SELECT
                    ws_web_site_sk,
                    ws_item_sk,
                    ws_order_number
                FROM web_sales
                WHERE ws_order_number IN (
                    SELECT wr_order_number
                    FROM web_returns
                )
            ) AS right ON (wr_item_sk = ws_item_sk) AND (wr_order_number = ws_order_number)
            WHERE wr_returned_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (CAST(d_date, 'Date') >= CAST('2000-08-19', 'Date')) AND (CAST(d_date, 'Date') <= (CAST('2000-08-19', 'Date') + toIntervalDay(14)))
            )
            GROUP BY ws_web_site_sk
        ) AS salesreturns, web_site
        WHERE wsr_web_site_sk = web_site_sk
        GROUP BY web_site_id
    )
SELECT
    channel,
    id,
    sum(sales) AS sales,
    sum(returns) AS returns,
    sum(profit) AS profit
FROM
(
    SELECT
        'store channel' AS channel,
        concat('store', s_store_id) AS id,
        sales,
        returns,
        profit - profit_loss AS profit
    FROM ssr
    UNION ALL
    SELECT
        'catalog channel' AS channel,
        concat('catalog_page', cp_catalog_page_id) AS id,
        sales,
        returns,
        profit - profit_loss AS profit
    FROM csr
    UNION ALL
    SELECT
        'web channel' AS channel,
        concat('web_site', web_site_id) AS id,
        sales,
        returns,
        profit - profit_loss AS profit
    FROM wsr
) AS x
GROUP BY
    channel,
    id
    WITH ROLLUP
ORDER BY
    channel ASC,
    id ASC
LIMIT 100
SETTINGS join_algorithm = 'parallel_hash'