--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) FIXED: 30 days -> INTERVAL 30 DAY
--- 4) Correlated subquery
select  
   count(distinct ws_order_number) as "order count"
  ,sum(ws_ext_ship_cost) as "total shipping cost"
  ,sum(ws_net_profit) as "total net profit"
from
   web_sales
where
ws_ship_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_date between '2002-3-01' and (cast('2002-3-01' as date) + INTERVAL 60 day))
and ws_ship_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_state = 'TX')
and ws_web_site_sk IN ( SELECT web_site_sk FROM web_site WHERE web_company_name = 'pri')
and ws_order_number IN (select ws_order_number FROM web_sales group by ws_order_number having count() > 1)
and ws_order_number NOT IN (select wr_order_number FROM web_returns)
order by count(distinct ws_order_number)
LIMIT 100;

