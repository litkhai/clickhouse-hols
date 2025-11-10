--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) FIXED: 30 days -> INTERVAL 30 DAY
WITH ws_wh AS
    (
        SELECT
            ws1.ws_order_number,
            ws1.ws_warehouse_sk AS wh1,
            ws2.ws_warehouse_sk AS wh2
        FROM web_sales AS ws1, web_sales AS ws2
        WHERE (ws1.ws_order_number = ws2.ws_order_number) AND (ws1.ws_warehouse_sk != ws2.ws_warehouse_sk)
    )
SELECT
    countDistinct(ws_order_number) AS `order count`,
    sum(ws_ext_ship_cost) AS `total shipping cost`,
    sum(ws_net_profit) AS `total net profit`
FROM web_sales AS ws1
WHERE (ws1.ws_ship_date_sk IN (
    SELECT d_date_sk
    FROM date_dim
    WHERE (d_date >= '2001-4-01') AND (d_date <= (CAST('2001-4-01', 'date') + toIntervalDay(60)))
)) AND (ws1.ws_ship_addr_sk IN (
    SELECT ca_address_sk
    FROM customer_address
    WHERE ca_state = 'GA'
)) AND (ws1.ws_web_site_sk IN (
    SELECT web_site_sk
    FROM web_site
    WHERE web_company_name = 'pri'
)) AND (ws1.ws_order_number IN (
    SELECT ws_order_number
    FROM ws_wh
)) AND (ws1.ws_order_number IN (
    SELECT wr_order_number
    FROM web_returns, ws_wh
    WHERE wr_order_number = ws_wh.ws_order_number
))
ORDER BY countDistinct(ws_order_number) ASC
LIMIT 100