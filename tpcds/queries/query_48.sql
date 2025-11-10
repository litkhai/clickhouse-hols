 select sum (ss_quantity)
 from store_sales, store, customer_demographics, customer_address
 where s_store_sk = ss_store_sk
 and ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999)
 and ss_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_country ='United States' and ca_state IN ('MO', 'AR', 'MN', 'MI', 'CO', 'TX','DE', 'NM', 'NV') )
 and ss_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE cd_marital_status IN ('D', 'U', 'W') and cd_education_status in('College','Advanced Degree', 'Primary') )
 and cd_demo_sk = ss_cdemo_sk
 and ss_addr_sk = ca_address_sk
 and  
 (
  ( 
   cd_marital_status = 'D'
   and 
   cd_education_status = 'College'
   and 
   ss_sales_price between 100.00 and 150.00  
   )
 or
  (
   cd_marital_status = 'U'
   and 
   cd_education_status = 'Advanced Degree'
   and 
   ss_sales_price between 50.00 and 100.00   
  )
 or 
 ( 
   cd_marital_status = 'W'
   and 
   cd_education_status = 'Primary'
   and 
   ss_sales_price between 150.00 and 200.00  
 )
 )
 and
 (
  (
  ca_state in ('MO', 'AR', 'MN')
  and ss_net_profit between 0 and 2000  
  )
 or
  (
  ca_state in ('MI', 'CO', 'TX')
  and ss_net_profit between 150 and 3000 
  )
 or
  (
  ca_state in ('DE', 'NM', 'NV')
  and ss_net_profit between 50 and 25000 
  )
 )
;
