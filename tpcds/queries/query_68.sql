--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
SELECT
    c_last_name,
    c_first_name,
    ca_city,
    bought_city,
    ss_ticket_number,
    extended_price,
    extended_tax,
    list_price
FROM
(
    SELECT
        ss_ticket_number,
        ss_customer_sk,
        ca_city AS bought_city,
        sum(ss_ext_sales_price) AS extended_price,
        sum(ss_ext_list_price) AS list_price,
        sum(ss_ext_tax) AS extended_tax
    FROM store_sales, household_demographics, customer_address
    WHERE (ss_sold_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE (date_dim.d_dom >= 1) AND (date_dim.d_dom <= 2) AND (date_dim.d_year IN (2000, 2000 + 1, 2000 + 2))
    )) AND (store_sales.ss_store_sk IN (
        SELECT s_store_sk
        FROM store
        WHERE s_city IN ('Shiloh', 'Glenwood')
    )) AND (store_sales.ss_hdemo_sk IN (
        SELECT hd_demo_sk
        FROM household_demographics
        WHERE (household_demographics.hd_dep_count = 5) OR (household_demographics.hd_vehicle_count = 4)
    )) AND (store_sales.ss_addr_sk = customer_address.ca_address_sk)
    GROUP BY
        ss_ticket_number,
        ss_customer_sk,
        ss_addr_sk,
        ca_city
) AS dn, customer, customer_address AS current_addr
WHERE (ss_customer_sk = c_customer_sk) AND (customer.c_current_addr_sk = current_addr.ca_address_sk) AND (current_addr.ca_city != bought_city)
ORDER BY
    c_last_name ASC,
    ss_ticket_number ASC
LIMIT 100