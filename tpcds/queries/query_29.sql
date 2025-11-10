select   
     i_item_id
    ,i_item_desc
    ,s_store_id
    ,s_store_name
    ,avg(ss_quantity)        as store_sales_quantity
    ,avg(sr_return_quantity) as store_returns_quantity
    ,avg(cs_quantity)        as catalog_sales_quantity
 from
    store_sales
   ,store_returns
   ,catalog_sales
   ,store
   ,item
 where
     ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy = 2 and d_year = 1998)
 and i_item_sk              = ss_item_sk
 and s_store_sk             = ss_store_sk
 and ss_customer_sk         = sr_customer_sk
 and ss_item_sk             = sr_item_sk
 and ss_ticket_number       = sr_ticket_number
 and sr_returned_date_sk IN (SELECT d_date_sk FROM date_dim WHERE
 d_moy between 2 and 2 + 3 and d_year = 1998)
 and sr_customer_sk         = cs_bill_customer_sk
 and sr_item_sk             = cs_item_sk
 and cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year in (1998,1998+1,1998+2))
 group by
    i_item_id
   ,i_item_desc
   ,s_store_id
   ,s_store_name
 order by
    i_item_id 
   ,i_item_desc
   ,s_store_id
   ,s_store_name
 limit 100;