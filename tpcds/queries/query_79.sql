--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unneccessary joins after 1) 
SELECT
    c_last_name,
    c_first_name,
    substr(s_city, 1, 30),
    ss_ticket_number,
    amt,
    profit
FROM
(
    SELECT
        ss_ticket_number,
        ss_customer_sk,
        store.s_city,
        sum(ss_coupon_amt) AS amt,
        sum(ss_net_profit) AS profit
    FROM store_sales, store
    WHERE (store_sales.ss_sold_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE (date_dim.d_dow = 1) AND (date_dim.d_year IN (1998, 1998 + 1, 1998 + 2))
    )) AND (store_sales.ss_hdemo_sk IN (
        SELECT hd_demo_sk
        FROM household_demographics
        WHERE (hd_dep_count = 0) OR (hd_vehicle_count > -1)
    )) AND ((store.s_number_employees >= 200) AND (store.s_number_employees <= 295)) AND (store_sales.ss_store_sk = store.s_store_sk) AND (store_sales.ss_store_sk IN (
        SELECT s_store_sk
        FROM store
        WHERE (s_number_employees >= 200) AND (s_number_employees <= 295)
    ))
    GROUP BY
        ss_ticket_number,
        ss_customer_sk,
        ss_addr_sk,
        store.s_city
) AS ms, customer
WHERE ss_customer_sk = c_customer_sk
ORDER BY
    c_last_name ASC,
    c_first_name ASC,
    substr(s_city, 1, 30) ASC,
    profit ASC
LIMIT 100