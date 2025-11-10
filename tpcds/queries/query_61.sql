select promotions,total,cast(promotions as decimal(15,4))/cast(total as decimal(15,4))*100
from
  (select sum(ss_ext_sales_price) promotions
   from  store_sales
   where ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2000 and d_moy  = 11)
   and   ss_promo_sk IN (SELECT p_promo_sk FROM promotion WHERE (p_channel_dmail = 'Y' or p_channel_email = 'Y' or p_channel_tv = 'Y'))
   and   ss_customer_sk IN (SELECT c_customer_sk FROM customer WHERE c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_gmt_offset = -6))
   and   ss_item_sk IN (SELECT i_item_sk FROM item WHERE i_category = 'Books')
) promotional_sales,
  (select sum(ss_ext_sales_price) total
   from  store_sales
   where ss_sold_date_sk  IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2000 and d_moy  = 11)
   and   ss_store_sk IN (SELECT s_store_sk FROM store WHERE s_gmt_offset = -6)
   and   ss_customer_sk IN (SELECT c_customer_sk FROM customer WHERE c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_gmt_offset = -6))
   and   ss_item_sk IN (SELECT i_item_sk FROM item WHERE i_category = 'Books')
) all_sales
order by promotions, total
LIMIT 100;