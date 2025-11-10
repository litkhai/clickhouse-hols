--- 1) Filtering joins rewritten to where join key IN ...
SELECT
    c_last_name,
    c_first_name,
    c_salutation,
    c_preferred_cust_flag,
    ss_ticket_number,
    cnt
FROM
(
    SELECT
        ss_ticket_number,
        ss_customer_sk,
        count(*) AS cnt
    FROM store_sales, date_dim, store, household_demographics
    WHERE (store_sales.ss_sold_date_sk = date_dim.d_date_sk) AND (store_sales.ss_sold_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE ((d_dom >= 1) AND (d_dom <= 2)) AND (d_year IN (1998, 1998 + 1, 1998 + 2))
    )) AND (date_dim.d_year IN (1998, 1998 + 1, 1998 + 2)) AND ((date_dim.d_dom >= 1) AND (date_dim.d_dom <= 2)) AND (store_sales.ss_store_sk = store.s_store_sk) AND (store.s_county IN ('Maverick County', 'Pennington County', 'San Miguel County', 'Walker County')) AND (store_sales.ss_store_sk IN (
        SELECT s_store_sk
        FROM store
        WHERE s_county IN ('Maverick County', 'Pennington County', 'San Miguel County', 'Walker County')
    )) AND (store_sales.ss_hdemo_sk = household_demographics.hd_demo_sk) AND ((household_demographics.hd_buy_potential = '501-1000') OR (household_demographics.hd_buy_potential = '0-500')) AND (household_demographics.hd_vehicle_count > 0) AND (multiIf(household_demographics.hd_vehicle_count > 0, household_demographics.hd_dep_count / household_demographics.hd_vehicle_count, NULL) > 1) AND (store_sales.ss_hdemo_sk IN (
        SELECT hd_demo_sk
        FROM household_demographics
        WHERE ((household_demographics.hd_buy_potential = '501-1000') OR (household_demographics.hd_buy_potential = '0-500')) AND (household_demographics.hd_vehicle_count > 0) AND (multiIf(household_demographics.hd_vehicle_count > 0, household_demographics.hd_dep_count / household_demographics.hd_vehicle_count, NULL) > 1)
    ))
    GROUP BY
        ss_ticket_number,
        ss_customer_sk
) AS dj, customer
WHERE (ss_customer_sk = c_customer_sk) AND ((cnt >= 1) AND (cnt <= 5))
ORDER BY
    cnt DESC,
    c_last_name ASC