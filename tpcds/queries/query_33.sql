WITH ss
     AS (SELECT i_manufact_id,
                Sum(ss_ext_sales_price) total_sales
         FROM   store_sales,
                item
         WHERE  i_manufact_id IN (SELECT i_manufact_id
                                  FROM   item
                                  WHERE  i_category IN ( 'Books' ))
                AND ss_item_sk = i_item_sk
                AND ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE
                d_year = 1999 AND d_moy = 3)
                AND ss_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE
                ca_gmt_offset = -5)
         GROUP  BY i_manufact_id),
     cs
     AS (SELECT i_manufact_id,
                Sum(cs_ext_sales_price) total_sales
         FROM   catalog_sales,
                item
         WHERE  i_manufact_id IN (SELECT i_manufact_id
                                  FROM   item
                                  WHERE  i_category IN ( 'Books' ))
                AND cs_item_sk = i_item_sk
                AND cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE
                d_year = 1999 AND d_moy = 3)
                AND cs_bill_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE
                ca_gmt_offset = -5)
         GROUP  BY i_manufact_id),
     ws
     AS (SELECT i_manufact_id,
                Sum(ws_ext_sales_price) total_sales
         FROM   web_sales,
                item
         WHERE  i_manufact_id IN (SELECT i_manufact_id
                                  FROM   item
                                  WHERE  i_category IN ( 'Books' ))
                AND ws_item_sk = i_item_sk
                AND ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE
                d_year = 1999 AND d_moy = 3)
                AND ws_bill_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE
                ca_gmt_offset = -5)
         GROUP  BY i_manufact_id)
SELECT i_manufact_id,
               Sum(total_sales) total_sales
FROM   (SELECT *
        FROM   ss
        UNION ALL
        SELECT *
        FROM   cs
        UNION ALL
        SELECT *
        FROM   ws) tmp1
GROUP  BY i_manufact_id
ORDER  BY total_sales
LIMIT 100;