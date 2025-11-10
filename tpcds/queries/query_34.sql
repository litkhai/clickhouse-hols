SELECT c_last_name,
       c_first_name,
       c_salutation,
       c_preferred_cust_flag,
       ss_ticket_number,
       cnt
FROM   (SELECT ss_ticket_number,
               ss_customer_sk,
               Count(*) cnt
        FROM   store_sales
        WHERE  store_sales.ss_sold_date_sk
                     IN (SELECT d_date_sk FROM date_dim WHERE
                            ( d_dom BETWEEN 1 AND 3 OR d_dom BETWEEN 25 AND 28 )
                            AND d_year IN ( 1999, 1999 + 1, 1999 + 2 ))
               AND store_sales.ss_hdemo_sk 
                     IN (SELECT hd_demo_sk FROM household_demographics WHERE
                            ( hd_buy_potential = '>10000'
                            OR hd_buy_potential = 'unknown' )
               AND hd_vehicle_count > 0
               AND ( CASE
                       WHEN hd_vehicle_count > 0 THEN
                       hd_dep_count /
                       hd_vehicle_count
                       ELSE NULL
                     END ) > 1.2)
               AND store_sales.ss_store_sk IN (SELECT s_store_sk FROM store WHERE
                     s_county IN (
                     'Levy County',
                     'Walker County',
                     'Franklin Parish',
                     'Mobile County',
                     'Luce County',
                     'Mesa County',
                     'Williamson County'))
        GROUP  BY ss_ticket_number,
                  ss_customer_sk) dn,
       customer
WHERE  ss_customer_sk = c_customer_sk
       AND cnt BETWEEN 15 AND 20
ORDER  BY c_last_name,
          c_first_name,
          c_salutation,
          c_preferred_cust_flag DESC;