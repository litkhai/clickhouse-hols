select dt.d_year
    ,item.i_brand_id brand_id
    ,item.i_brand brand
    ,sum(ss_ext_sales_price) ext_price
 from date_dim dt
     ,store_sales
     ,item
 where dt.d_date_sk = store_sales.ss_sold_date_sk
    and store_sales.ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy=11 and d_year=1999)
    and store_sales.ss_item_sk = item.i_item_sk
    and store_sales.ss_item_sk IN (SELECT i_item_sk FROM item WHERE item.i_manager_id = 1) 
    and item.i_manager_id = 1
    and dt.d_moy=11
    and dt.d_year=1999
 group by dt.d_year
    ,item.i_brand
    ,item.i_brand_id
 order by dt.d_year
    ,ext_price desc
    ,brand_id
LIMIT 100 ;