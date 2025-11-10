--- 1) Had to move joins condition from several OR parts to upper level - we could not rewrite it from CROSS JOIN to INNER
--- 2) Filtering joins rewritten to where join key IN ...
--- 3) Remove unnecessary joins after 1)
select avg(ss_quantity)
       ,avg(ss_ext_sales_price)
       ,avg(ss_ext_wholesale_cost)
       ,sum(ss_ext_wholesale_cost)
 from store_sales
     ,store
     ,customer_demographics
     ,household_demographics
     ,customer_address
 where s_store_sk = ss_store_sk
 and ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2001)
 and ss_hdemo_sk=hd_demo_sk
 and ss_hdemo_sk in (SELECT hd_demo_sk FROM household_demographics WHERE hd_dep_count in (1,3))
 and cd_demo_sk = ss_cdemo_sk
 and ss_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE cd_marital_status IN ('U', 'M', 'D') and cd_education_status IN ('Advanced Degree', 'Primary', 'Secondary'))
 and ss_addr_sk = ca_address_sk
 and ss_addr_sk in (SELECT ca_address_sk FROM customer_address WHERE ca_country = 'United States' and
  ca_state IN ('MO', 'OK', 'TX', 'KS', 'PA', 'NM', 'NY', 'CO', 'MN'))
and
 ((
  cd_marital_status = 'S'
  and cd_education_status = '4 yr Degree'
  and ss_sales_price between 100.00 and 150.00
  and hd_dep_count = 3   
     )or
     (
  cd_marital_status = 'W'
  and cd_education_status = 'Secondary'
  and ss_sales_price between 50.00 and 100.00   
  and hd_dep_count = 1
     ) or 
     (
  cd_marital_status = 'U'
  and cd_education_status = 'College'
  and ss_sales_price between 150.00 and 200.00 
  and hd_dep_count = 1  
     )
)
 and ((ca_country = 'United States'
  and ca_state in ('MO', 'OK', 'TX')
  and ss_net_profit between 100 and 200  
     ) or
     (ca_country = 'United States'
  and ca_state in ('KS', 'PA', 'NM')
  and ss_net_profit between 150 and 300  
     ) or
     (ca_country = 'United States'
  and ca_state in ('NY', 'CO', 'MN')
  and ss_net_profit between 50 and 250  
     ));