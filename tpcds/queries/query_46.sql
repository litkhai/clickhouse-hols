select c_last_name
      ,c_first_name
      ,ca_city
      ,bought_city
      ,ss_ticket_number
      ,amt
      ,profit 
from
 (select ss_ticket_number
        ,ss_customer_sk
        ,ca_city bought_city
        ,sum(ss_coupon_amt) amt
        ,sum(ss_net_profit) profit
  from store_sales,customer_address 
  where 
    store_sales.ss_sold_date_sk IN (
      SELECT d_date_sk FROM date_dim WHERE d_dow in (6,0) and d_year in (1999,1999+1,1999+2))
  and store_sales.ss_store_sk IN (
      SELECT s_store_sk FROM store WHERE store.s_city in ('Bethel','Oakland','Salem','Fairview','Wildwood'))
  and store_sales.ss_hdemo_sk IN (
      SELECT hd_demo_sk from household_demographics where (hd_dep_count = 6 or hd_vehicle_count= 3))
  and store_sales.ss_addr_sk = customer_address.ca_address_sk
  group by ss_ticket_number,ss_customer_sk,ss_addr_sk,ca_city) dn
  ,customer,customer_address current_addr
  where ss_customer_sk = c_customer_sk
    and customer.c_current_addr_sk = current_addr.ca_address_sk
    and current_addr.ca_city <> bought_city
order by c_last_name
        ,c_first_name
        ,ca_city
        ,bought_city
        ,ss_ticket_number
LIMIT 100;