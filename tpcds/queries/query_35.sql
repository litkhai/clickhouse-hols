with ss_denorm as
 (

    select count(*) > 0 as ss_exists, ss_customer_sk
    from store_sales
    where ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_qoy < 4)
    group by ss_customer_sk
 ),
ws_denorm as
 (
    select count(*) > 0 as ws_exists, ws_bill_customer_sk
    from web_sales
    where ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_qoy < 4) 
    group by ws_bill_customer_sk
 ),
cs_denorm as
 (
    select count(*) > 0 as cs_exists, cs_ship_customer_sk
    from catalog_sales
    where cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_qoy < 4)
    group by cs_ship_customer_sk
 )
 select
  ca_state,
  cd_gender,
  cd_marital_status,
  cd_dep_count,
  count(*) cnt1,
  max(cd_dep_count),
  avg(cd_dep_count),
  sum(cd_dep_count),
  cd_dep_employed_count,
  count(*) cnt2,
  max(cd_dep_employed_count),
  avg(cd_dep_employed_count),
  sum(cd_dep_employed_count),
  cd_dep_college_count,
  count(*) cnt3,
  max(cd_dep_college_count),
  avg(cd_dep_college_count),
  sum(cd_dep_college_count)
 from
  customer c,customer_address ca,customer_demographics,
  ss_denorm, ws_denorm, cs_denorm
 where
  c.c_current_addr_sk = ca.ca_address_sk and
  cd_demo_sk = c.c_current_cdemo_sk and 
  c.c_customer_sk = ss_customer_sk and
  c.c_customer_sk = ws_bill_customer_sk and 
  c.c_customer_sk = cs_ship_customer_sk and
  ss_exists and (cs_exists or ws_exists)
 group by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 order by ca_state,
          cd_gender,
          cd_marital_status,
          cd_dep_count,
          cd_dep_employed_count,
          cd_dep_college_count
 limit 100;