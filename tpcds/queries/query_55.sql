select i_brand_id brand_id, i_brand brand,
    sum(ss_ext_sales_price) ext_price
 from store_sales, item
 where  ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy=11
    and d_year=1999
)
    and ss_item_sk = i_item_sk
    and i_manager_id=9
 group by i_brand, i_brand_id
 order by ext_price desc, i_brand_id 
 LIMIT 100 ;