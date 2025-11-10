select i_item_id, 
        avg(cs_quantity) agg1,
        avg(cs_list_price) agg2,
        avg(cs_coupon_amt) agg3,
        avg(cs_sales_price) agg4 
 from catalog_sales, item
 where cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999) and
       cs_item_sk = i_item_sk and
       cs_bill_cdemo_sk IN (SELECT cd_demo_sk FROM customer_demographics WHERE
       cd_gender = 'M' and 
       cd_marital_status = 'W' and
       cd_education_status = 'Secondary') and
       cs_promo_sk IN ( SELECT p_promo_sk FROM promotion WHERE
       (p_channel_email = 'N' or p_channel_event = 'N'))
 group by i_item_id
 order by i_item_id
 limit 100;