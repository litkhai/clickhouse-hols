SELECT dt.d_year, 
       item.i_category_id, 
       item.i_category, 
       Sum(ss_ext_sales_price) 
FROM   date_dim dt, 
       store_sales, 
       item 
WHERE  store_sales.ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy = 12 AND d_year = 2000)
       AND store_sales.ss_sold_date_sk = dt.d_date_sk
       AND store_sales.ss_item_sk = item.i_item_sk 
       AND dt.d_moy = 12 AND dt.d_year = 2000
       AND item.i_manager_id = 1
GROUP  BY dt.d_year, 
          item.i_category_id, 
          item.i_category 
ORDER  BY Sum(ss_ext_sales_price) DESC, 
          dt.d_year, 
          item.i_category_id, 
          item.i_category
LIMIT 100; 
