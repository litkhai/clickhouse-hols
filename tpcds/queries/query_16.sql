SELECT
         Count(DISTINCT cs_order_number) AS order_count ,
         Sum(cs_ext_ship_cost)           AS total_shipping_cost ,
         Sum(cs_net_profit)              AS total_net_profit
FROM     catalog_sales cs1
WHERE    
         cs1.cs_ship_date_sk IN (SELECT d_date_sk FROM date_dim WHERE Cast(d_date AS DATE) BETWEEN Cast('2002-3-01' AS DATE) AND (
                  Cast('2002-5-01' AS DATE)))
AND      cs1.cs_ship_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_state = 'IA')
AND      cs1.cs_call_center_sk IN (SELECT cc_call_center_sk FROM call_center WHERE cc_county IN ('Brule County',
'Gonzales County',
'Delta County',
'Falls County',
'Kingman County'))
AND cs_order_number IN
         (
                SELECT cs_order_number 
                FROM   catalog_sales cs2
                GROUP BY cs_order_number HAVING COUNT(cs2.cs_warehouse_sk)>1
         )
AND cs_order_number NOT IN
         (
                SELECT cr_order_number
                FROM   catalog_returns
         )
ORDER BY count(DISTINCT cs_order_number)
LIMIT 100;