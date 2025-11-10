select 
    i_product_name
    ,i_brand
    ,i_class
    ,i_category
    ,avg(inv_quantity_on_hand) qoh
from inventory, item
where 
    inv_date_sk IN ( SELECT d_date_sk FROM date_dim WHERE
       d_month_seq BETWEEN 1200 AND 1200 + 11)
    and inv_item_sk=i_item_sk
group by rollup(i_product_name
               ,i_brand
               ,i_class
               ,i_category)
order by qoh, i_product_name, i_brand, i_class, i_category
LIMIT 100