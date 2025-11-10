select i_item_id
       ,i_item_desc
       ,i_current_price
 from item, catalog_sales
 where i_current_price between 15 and 15 + 30
 and i_item_sk IN (SELECT inv_item_sk FROM inventory WHERE 
 inv_date_sk in (select d_date_sk FROM date_dim WHERE
 cast(d_date as date) between cast('2000-03-14' as date) and (cast('2000-03-14' as date) + interval 60 day))
 and inv_quantity_on_hand between 100 and 500)
 and i_manufact_id in (893,754,668,831)
 and cs_item_sk = i_item_sk
 group by i_item_id,i_item_desc,i_current_price
 order by i_item_id