--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
SELECT
    ss_customer_sk,
    sum(act_sales) AS sumsales
FROM
(
    SELECT
        ss_item_sk,
        ss_ticket_number,
        ss_customer_sk,
        multiIf(sr_return_quantity IS NOT NULL, (ss_quantity - sr_return_quantity) * ss_sales_price, ss_quantity * ss_sales_price) AS act_sales
    FROM store_sales
    LEFT JOIN store_returns ON (sr_item_sk = ss_item_sk) AND (sr_ticket_number = ss_ticket_number)
    WHERE sr_reason_sk IN (SELECT r_reason_sk FROM reason WHERE r_reason_desc = 'Stopped working')
) AS t
GROUP BY ss_customer_sk
ORDER BY
    sumsales ASC,
    ss_customer_sk ASC
LIMIT 100