SELECT
         i_item_id ,
         i_item_desc ,
         i_category ,
         i_class ,
         i_current_price ,
         Sum(cs_ext_sales_price) AS itemrevenue ,
         Sum(cs_ext_sales_price)*100/Sum(Sum(cs_ext_sales_price)) OVER (partition BY i_class) AS revenueratio
FROM     catalog_sales,
         item
WHERE    cs_item_sk = i_item_sk
AND      i_category IN ('Children',
                        'Women',
                        'Electronics')
AND      cs_sold_date_sk IN (select d_date_sk FROM date_dim WHERE
    Cast(d_date AS DATE) BETWEEN Cast('2001-02-03' AS DATE) AND      (
                  Cast('2001-03-03' AS DATE)))
GROUP BY i_item_id ,
         i_item_desc ,
         i_category ,
         i_class ,
         i_current_price
ORDER BY i_category ,
         i_class ,
         i_item_id ,
         i_item_desc ,
         revenueratio
LIMIT 100;