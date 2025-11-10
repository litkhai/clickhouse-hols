--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) FIXED: 30 days -> INTERVAL 30 DAY
--- 4) Correlated subquery
WITH 
 ws_corr AS 
 (
    SELECT
    ws_item_sk as item_sk,
    avg(ws_ext_discount_amt) as avg_ws_ext_discount_amt 
    FROM web_sales
    WHERE ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_date between '2002-01-12' and (cast('2002-01-12' as date) + INTERVAL 90 day))
    GROUP BY ws_item_sk
 )

select  
   sum(ws_ext_discount_amt)  as "Excess Discount Amount" 
from 
    web_sales,
    ws_corr
where
ws_item_sk IN (select i_item_sk from item where i_manufact_id = 744)
and ws_sold_date_sk in (select d_date_sk FROM date_dim WHERE d_date between '2002-01-12' and (cast('2002-01-12' as date) + INTERVAL 90 day))
and item_sk = ws_item_sk
and ws_ext_discount_amt  > 1.3 * avg_ws_ext_discount_amt
order by sum(ws_ext_discount_amt)
LIMIT 100;