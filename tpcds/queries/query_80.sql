--- 1) FIXED: 30 days -> INTERVAL 30 DAY
--- 2) Filtering joins rewritten to where join key IN ...
--- 3) Remove unnecessary joins after 1)
WITH
    ssr AS
    (
        SELECT
            s_store_id AS store_id,
            sum(ss_ext_sales_price) AS sales,
            sum(coalesce(sr_return_amt, 0)) AS returns,
            sum(ss_net_profit - coalesce(sr_net_loss, 0)) AS profit
        FROM store_sales
        LEFT JOIN store_returns ON (ss_item_sk = sr_item_sk) AND (ss_ticket_number = sr_ticket_number), store
        WHERE (ss_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-28', 'date')) AND (d_date <= (CAST('2002-08-28', 'date') + toIntervalDay(30)))
        )) AND (ss_store_sk = s_store_sk) AND (ss_item_sk IN (
            SELECT i_item_sk
            FROM item
            WHERE i_current_price > 50
        )) AND (ss_promo_sk IN (
            SELECT p_promo_sk
            FROM promotion
            WHERE p_channel_tv = 'N'
        ))
        GROUP BY s_store_id
    ),
    csr AS
    (
        SELECT
            cp_catalog_page_id AS catalog_page_id,
            sum(cs_ext_sales_price) AS sales,
            sum(coalesce(cr_return_amount, 0)) AS returns,
            sum(cs_net_profit - coalesce(cr_net_loss, 0)) AS profit
        FROM catalog_sales
        LEFT JOIN catalog_returns ON (cs_item_sk = cr_item_sk) AND (cs_order_number = cr_order_number), catalog_page
        WHERE (cs_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-28', 'date')) AND (d_date <= (CAST('2002-08-28', 'date') + toIntervalDay(30)))
        )) AND (cs_catalog_page_sk = cp_catalog_page_sk) AND (cs_item_sk IN (
            SELECT i_item_sk
            FROM item
            WHERE i_current_price > 50
        )) AND (cs_promo_sk IN (
            SELECT p_promo_sk
            FROM promotion
            WHERE p_channel_tv = 'N'
        ))
        GROUP BY cp_catalog_page_id
    ),
    wsr AS
    (
        SELECT
            web_site_id,
            sum(ws_ext_sales_price) AS sales,
            sum(coalesce(wr_return_amt, 0)) AS returns,
            sum(ws_net_profit - coalesce(wr_net_loss, 0)) AS profit
        FROM web_sales
        LEFT JOIN web_returns ON (ws_item_sk = wr_item_sk) AND (ws_order_number = wr_order_number), web_site
        WHERE (ws_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-28', 'date')) AND (d_date <= (CAST('2002-08-28', 'date') + toIntervalDay(30)))
        )) AND (ws_web_site_sk = web_site_sk) AND (ws_item_sk IN (
            SELECT i_item_sk
            FROM item
            WHERE i_current_price > 50
        )) AND (ws_promo_sk IN (
            SELECT p_promo_sk
            FROM promotion
            WHERE p_channel_tv = 'N'
        ))
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
        concat('store', store_id) AS id,
        sales,
        returns,
        profit
    FROM ssr
    UNION ALL
    SELECT
        'catalog channel' AS channel,
        concat('catalog_page', catalog_page_id) AS id,
        sales,
        returns,
        profit
    FROM csr
    UNION ALL
    SELECT
        'web channel' AS channel,
        concat('web_site', web_site_id) AS id,
        sales,
        returns,
        profit
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