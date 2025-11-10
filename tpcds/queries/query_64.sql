xxx --- Timeouts anyway
WITH
    cs_ui AS
    (
        SELECT
            cs_item_sk,
            sum(cs_ext_list_price) AS sale,
            sum((cr_refunded_cash + cr_reversed_charge) + cr_store_credit) AS refund
        FROM
            catalog_sales,
            catalog_returns
        WHERE 
            cs_item_sk = cr_item_sk 
            AND cs_order_number = cr_order_number
        GROUP BY cs_item_sk
        HAVING 
            sum(cs_ext_list_price) > 2 * sum(cr_refunded_cash + cr_reversed_charge + cr_store_credit)
    ),
    unequal_marital_status AS 
    (
        SELECT DISTINCT
            cd1.cd_demo_sk as demo_sk
        FROM
            store_sales,
            customer,
            customer_demographics as cd1,
            customer_demographics as cd2
        WHERE 
            ss_customer_sk = c_customer_sk
            AND c_current_cdemo_sk = cd2.cd_demo_sk
            AND ss_cdemo_sk = cd1.cd_demo_sk
            AND cd1.cd_marital_status != cd2.cd_marital_status
    ),
    cross_sales_pre AS
    (  
        SELECT
            ss_item_sk,
            ss_store_sk,
            ss_addr_sk,
            c_current_addr_sk,
            ss_sold_date_sk,
            c_first_sales_date_sk,
            c_first_shipto_date_sk,
            count(*) AS cnt_pre,
            sum(ss_wholesale_cost) AS s1_pre,
            sum(ss_list_price) AS s2_pre,
            sum(ss_coupon_amt) AS s3_pre
        FROM 
            store_sales, customer, store_returns
        WHERE
            ss_item_sk = sr_item_sk
            AND ss_ticket_number = sr_ticket_number
            AND ss_ticket_number IN (SELECT sr_ticket_number FROM store_returns)
            AND ss_item_sk IN (SELECT cs_item_sk FROM cs_ui)
            AND ss_customer_sk = c_customer_sk
            AND ss_customer_sk IN (
                SELECT c_customer_sk FROM customer 
                WHERE
                    c_current_cdemo_sk IN (SELECT demo_sk FROM unequal_marital_status)
                    AND c_current_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE hd_income_band_sk IN (SELECT ib_income_band_sk FROM income_band))
                    AND c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address)
                )
            AND c_customer_sk IN (
                SELECT c_customer_sk FROM customer 
                WHERE
                    c_current_cdemo_sk IN (SELECT demo_sk FROM unequal_marital_status)
                    AND c_current_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics)
                    AND c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address)
                )
            AND ss_item_sk IN (
                SELECT i_item_sk FROM item WHERE 
                (i_color IN ('gainsboro', 'light', 'drab', 'steel', 'misty', 'powder')) 
                AND ((i_current_price >= 58) AND (i_current_price <= (58 + 10)))
                AND ((i_current_price >= (58 + 1)) AND (i_current_price <= (58 + 15)))
                )
            AND ss_promo_sk IN (SELECT p_promo_sk FROM promotion)
            AND ss_hdemo_sk IN (
                SELECT hd_demo_sk FROM household_demographics WHERE hd_income_band_sk IN (
                    SELECT ib_income_band_sk FROM income_band
                    )
                )
        GROUP BY 
            ss_item_sk,
            ss_store_sk,
            ss_addr_sk,
            c_current_addr_sk,
            ss_sold_date_sk,
            c_first_sales_date_sk,
            c_first_shipto_date_sk
    ),
    cross_sales AS
    (
        SELECT
            i_product_name AS product_name,
            i_item_sk AS item_sk,
            s_store_name AS store_name,
            s_zip AS store_zip,
            ad1.ca_street_number AS b_street_number,
            ad1.ca_street_name AS b_street_name,
            ad1.ca_city AS b_city,
            ad1.ca_zip AS b_zip,
            ad2.ca_street_number AS c_street_number,
            ad2.ca_street_name AS c_street_name,
            ad2.ca_city AS c_city,
            ad2.ca_zip AS c_zip,
            d1.d_year AS syear,
            d2.d_year AS fsyear,
            d3.d_year AS s2year,
            sum(cnt_pre) AS cnt,
            sum(s1_pre) AS s1,
            sum(s2_pre) AS s2,
            sum(s3_pre) AS s3
        FROM 
            cross_sales_pre, 
            store,
            customer_address AS ad1,
            customer_address AS ad2,
            item,
            date_dim AS d1,
            date_dim AS d2, 
            date_dim AS d3
        WHERE 
            ss_store_sk = s_store_sk
            AND ss_sold_date_sk = d1.d_date_sk
            AND ss_item_sk = i_item_sk
            AND ss_addr_sk = ad1.ca_address_sk
            AND c_first_sales_date_sk = d2.d_date_sk
            AND c_first_shipto_date_sk = d3.d_date_sk
            AND syear IN (2001, 2001+1)
        GROUP BY
            i_product_name,
            i_item_sk,
            s_store_name,
            s_zip,
            ad1.ca_street_number,
            ad1.ca_street_name,
            ad1.ca_city,
            ad1.ca_zip,
            ad2.ca_street_number,
            ad2.ca_street_name,
            ad2.ca_city,
            ad2.ca_zip,
            d1.d_year,
            d2.d_year,
            d3.d_year
    )
SELECT
    cs1.product_name,
    cs1.store_name,
    cs1.store_zip,
    cs1.b_street_number,
    cs1.b_street_name,
    cs1.b_city,
    cs1.b_zip,
    cs1.c_street_number,
    cs1.c_street_name,
    cs1.c_city,
    cs1.c_zip,
    cs1.syear,
    cs1.cnt,
    cs1.s1 AS s11,
    cs1.s2 AS s21,
    cs1.s3 AS s31,
    cs2.s1 AS s12,
    cs2.s2 AS s22,
    cs2.s3 AS s32,
    cs2.syear,
    cs2.cnt
FROM cross_sales AS cs1, cross_sales AS cs2
WHERE (cs1.item_sk = cs2.item_sk) AND (cs1.syear = 2001) AND (cs2.syear = (2001 + 1)) AND (cs2.cnt <= cs1.cnt) AND (cs1.store_name = cs2.store_name) AND (cs1.store_zip = cs2.store_zip)
ORDER BY
    cs1.product_name ASC,
    cs1.store_name ASC,
    cs2.cnt ASC,
    cs1.s1 ASC,
    cs2.s1 ASC