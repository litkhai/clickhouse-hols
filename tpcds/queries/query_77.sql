--- 1) FIXED: 30 days -> INTERVAL 30 DAY
--- 2) Filtering joins rewritten to where join key IN ...
--- 3) Remove unnecessary joins after 1)
--- 4) Fix lost on condition for 'cr, cs'
WITH
    ss AS
    (
        SELECT
            ss_store_sk,
            sum(ss_ext_sales_price) AS sales,
            sum(ss_net_profit) AS profit
        FROM store_sales
        WHERE ss_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY ss_store_sk
    ),
    sr AS
    (
        SELECT
            sr_store_sk,
            sum(sr_return_amt) AS returns,
            sum(sr_net_loss) AS profit_loss
        FROM store_returns
        WHERE sr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY sr_store_sk
    ),
    cs AS
    (
        SELECT
            cs_call_center_sk,
            sum(cs_ext_sales_price) AS sales,
            sum(cs_net_profit) AS profit
        FROM catalog_sales
        WHERE cs_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY cs_call_center_sk
    ),
    cr AS
    (
        SELECT
            cr_call_center_sk,
            sum(cr_return_amount) AS returns,
            sum(cr_net_loss) AS profit_loss
        FROM catalog_returns
        WHERE cr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY cr_call_center_sk
    ),
    ws AS
    (
        SELECT
            ws_web_page_sk,
            sum(ws_ext_sales_price) AS sales,
            sum(ws_net_profit) AS profit
        FROM web_sales, web_page
        WHERE ws_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY ws_web_page_sk
    ),
    wr AS
    (
        SELECT
            wr_web_page_sk,
            sum(wr_return_amt) AS returns,
            sum(wr_net_loss) AS profit_loss
        FROM web_returns
        WHERE wr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_date >= CAST('2002-08-26', 'date')) AND (d_date <= (CAST('2002-08-26', 'date') + toIntervalDay(30)))
        )
        GROUP BY wr_web_page_sk
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
        ss.ss_store_sk AS id,
        sales,
        coalesce(returns, 0) AS returns,
        profit - coalesce(profit_loss, 0) AS profit
    FROM ss
    LEFT JOIN sr ON ss.ss_store_sk = sr.sr_store_sk
    INNER JOIN store ON ss.ss_store_sk = store.s_store_sk
    UNION ALL
    SELECT
        'catalog channel' AS channel,
        cs_call_center_sk AS id,
        sales,
        returns,
        profit - profit_loss AS profit
    FROM cs, cr
    WHERE cs.cs_call_center_sk = cr.cr_call_center_sk
    UNION ALL
    SELECT
        'web channel' AS channel,
        ws.ws_web_page_sk AS id,
        sales,
        coalesce(returns, 0) AS returns,
        profit - coalesce(profit_loss, 0) AS profit
    FROM ws
    LEFT JOIN wr ON ws.ws_web_page_sk = wr.wr_web_page_sk
    INNER JOIN web_page ON ws.ws_web_page_sk = web_page.wp_web_page_sk
) AS x
GROUP BY
    channel,
    id
    WITH ROLLUP
ORDER BY
    channel ASC,
    id ASC
LIMIT 100