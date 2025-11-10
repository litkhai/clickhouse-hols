with ss as (
select i_item_id, sum(ss_ext_sales_price) total_sales
from store_sales, item
where
    i_item_id in (select i_item_id from item where i_category in ('Music'))
    and ss_item_sk  = i_item_sk
    and ss_item_sk IN (SELECT i_item_sk FROM item WHERE i_category IN ('Music'))
    and ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_moy = 8)
    and ss_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_gmt_offset = -5)
group by i_item_id),
cs as (
select i_item_id, sum(cs_ext_sales_price) total_sales
from catalog_sales, item
where 
    i_item_id in (select i_item_id from item where i_category in ('Music'))
    and cs_item_sk = i_item_sk
    and cs_item_sk IN (SELECT i_item_sk FROM item WHERE i_category IN ('Music'))
    and cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_moy = 8)
    and cs_bill_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_gmt_offset = -5)
group by i_item_id),
ws as (
select i_item_id, sum(ws_ext_sales_price) total_sales
from web_sales, item
where
 i_item_id in (select i_item_id from item where i_category in ('Music'))
 and ws_item_sk = i_item_sk
 and ws_item_sk IN (SELECT i_item_sk FROM item WHERE i_category IN ('Music'))
 and ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 and d_moy = 8)
 and ws_bill_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_gmt_offset = -5)
 group by i_item_id)
 select i_item_id ,sum(total_sales) total_sales
 from  (select * from ss 
        union all
        select * from cs 
        union all
        select * from ws) tmp1
 group by i_item_id
 order by i_item_id, total_sales
 LIMIT 100;