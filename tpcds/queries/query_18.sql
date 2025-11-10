select i_item_id,
        ca_country,
        ca_state, 
        ca_county,
        avg( cast(COALESCE(cs_quantity, 0) as decimal(12,2))) agg1,
        avg( cast(COALESCE(cs_list_price, 0) as decimal(12,2))) agg2,
        avg( cast(COALESCE(cs_coupon_amt, 0) as decimal(12,2))) agg3,
        avg( cast(COALESCE(cs_sales_price, 0) as decimal(12,2))) agg4,
        avg( cast(COALESCE(cs_net_profit, 0) as decimal(12,2))) agg5,
        avg( cast(COALESCE(c_birth_year, 0) as decimal(12,2))) agg6,
        avg( cast(COALESCE(cd_dep_count, 0) as decimal(12,2))) agg7
 from catalog_sales, customer, customer_demographics, customer_address, item
 where cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2000) and
       cs_item_sk = i_item_sk and
       cs_bill_cdemo_sk = cd_demo_sk and
       cs_bill_cdemo_sk IN (select cd_demo_sk from customer_demographics
              where cd_gender = 'F' and cd_education_status = 'Secondary')
       and
       cs_bill_customer_sk = c_customer_sk and
       c_current_addr_sk = ca_address_sk and
       c_birth_month in (8, 4, 2, 5, 11, 9) and     
       ca_state in ('WI', 'WY', 'PA', 'VT', 'MT', 'CT', 'OR')
 group by rollup (i_item_id, ca_country, ca_state, ca_county)
 order by ca_country,
        ca_state, 
        ca_county,
        i_item_id
 LIMIT 100;