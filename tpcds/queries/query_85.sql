--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) Union possible values in OR filter statements and convert to prefiltering join
select  substr(r_reason_desc,1,20)
       ,avg(ws_quantity)
       ,avg(wr_refunded_cash)
       ,avg(wr_fee)
 from web_sales, web_returns, web_page, customer_demographics cd1,
      customer_demographics cd2, customer_address, reason 
 where ws_web_page_sk = wp_web_page_sk
   and ws_item_sk = wr_item_sk
   and ws_order_number = wr_order_number
   and ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2002)
   and cd1.cd_demo_sk = wr_refunded_cdemo_sk 
   and cd2.cd_demo_sk = wr_returning_cdemo_sk
   and ca_address_sk = wr_refunded_addr_sk
   and wr_refunded_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_country = 'United States' and ca_state IN ('MI', 'KY', 'OH', 'OK', 'CA', 'VA', 'NE', 'MT', 'MO') )
   and wr_refunded_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE (cd_marital_status = 'M' and cd_education_status = '2 yr Degree') or (cd_marital_status = 'D' and cd_education_status = 'Primary') or (cd_marital_status = 'W' and cd_education_status = 'Secondary'))
   and wr_returning_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE (cd_marital_status = 'M' and cd_education_status = '2 yr Degree') or (cd_marital_status = 'D' and cd_education_status = 'Primary') or (cd_marital_status = 'W' and cd_education_status = 'Secondary'))
   and r_reason_sk = wr_reason_sk
   and
   (
    (
     cd1.cd_marital_status = 'M'
     and
     cd1.cd_marital_status = cd2.cd_marital_status
     and
     cd1.cd_education_status = '2 yr Degree'
     and 
     cd1.cd_education_status = cd2.cd_education_status
     and
     ws_sales_price between 100.00 and 150.00
    )
   or
    (
     cd1.cd_marital_status = 'D'
     and
     cd1.cd_marital_status = cd2.cd_marital_status
     and
     cd1.cd_education_status = 'Primary' 
     and
     cd1.cd_education_status = cd2.cd_education_status
     and
     ws_sales_price between 50.00 and 100.00
    )
   or
    (
     cd1.cd_marital_status = 'W'
     and
     cd1.cd_marital_status = cd2.cd_marital_status
     and
     cd1.cd_education_status = 'Secondary'
     and
     cd1.cd_education_status = cd2.cd_education_status
     and
     ws_sales_price between 150.00 and 200.00
    )
   )
   and
   (
    (
     ca_country = 'United States'
     and
     ca_state in ('MI', 'KY', 'OH')
     and ws_net_profit between 100 and 200  
    )
    or
    (
     ca_country = 'United States'
     and
     ca_state in ('OK', 'CA', 'VA')
     and ws_net_profit between 150 and 300  
    )
    or
    (
     ca_country = 'United States'
     and
     ca_state in ('NE', 'MT', 'MO')
     and ws_net_profit between 50 and 250  
    )
   )
group by r_reason_desc
order by substr(r_reason_desc,1,20)
        ,avg(ws_quantity)
        ,avg(wr_refunded_cash)
        ,avg(wr_fee)
LIMIT 100;

