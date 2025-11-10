select i_item_id
      ,i_item_desc 
      ,i_category 
      ,i_class 
      ,i_current_price
      ,sum(ss_ext_sales_price) as itemrevenue 
      ,sum(ss_ext_sales_price)*100/sum(sum(ss_ext_sales_price)) over
          (partition by i_class) as revenueratio
from  
   store_sales
      ,item 
where 
   ss_item_sk = i_item_sk 
   and ss_item_sk IN (select i_item_sk from item where i_category in ('Sports', 'Books', 'Shoes')) 
   and i_category in ('Sports', 'Books', 'Shoes')
   and ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim where
      d_date::Date between cast('1998-07-01' as date) and (cast('1998-07-01' as date) + interval 30 day))
group by 
   i_item_id
        ,i_item_desc 
        ,i_category
        ,i_class
        ,i_current_price
order by 
   i_category
        ,i_class
        ,i_item_id
        ,i_item_desc
        ,revenueratio;