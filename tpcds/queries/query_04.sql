--- 1) Rewritten group by in join to two steps - GROUP BY + separate JOIN
WITH year_total AS
    (
        SELECT
            c_customer_id AS customer_id,
            dyear,
            year_total,
            's' AS sale_type
        FROM
        (
            SELECT
                ss_customer_sk,
                d_year AS dyear,
                Sum((((ss_ext_list_price - ss_ext_wholesale_cost) - ss_ext_discount_amt) + ss_ext_sales_price) / 2) AS year_total
            FROM store_sales, date_dim
            WHERE ss_sold_date_sk = d_date_sk
            GROUP BY
                ss_customer_sk,
                d_year
        ) AS yt, customer
        WHERE c_customer_sk = ss_customer_sk
        UNION ALL
        SELECT
            c_customer_id AS customer_id,
            dyear,
            year_total,
            'c' AS sale_type
        FROM
        (
            SELECT
                cs_bill_customer_sk,
                d_year AS dyear,
                Sum((((cs_ext_list_price - cs_ext_wholesale_cost) - cs_ext_discount_amt) + cs_ext_sales_price) / 2) AS year_total
            FROM catalog_sales, date_dim
            WHERE cs_sold_date_sk = d_date_sk
            GROUP BY
                cs_bill_customer_sk,
                d_year
        ) AS yt, customer
        WHERE cs_bill_customer_sk = c_customer_sk
        UNION ALL
        SELECT
            c_customer_id AS customer_id,
            dyear,
            year_total,
            'w' AS sale_type
        FROM
        (
            SELECT
                ws_bill_customer_sk,
                d_year AS dyear,
                Sum((((ws_ext_list_price - ws_ext_wholesale_cost) - ws_ext_discount_amt) + ws_ext_sales_price) / 2) AS year_total
            FROM web_sales, date_dim
            WHERE ws_sold_date_sk = d_date_sk
            GROUP BY
                ws_bill_customer_sk,
                d_year
        ) AS yt, customer
        WHERE ws_bill_customer_sk = c_customer_sk
    )
SELECT
    t_s_secyear.customer_id,
    customer.c_first_name,
    customer.c_last_name,
    customer.c_preferred_cust_flag
FROM year_total AS t_s_firstyear, year_total AS t_s_secyear, year_total AS t_c_firstyear, year_total AS t_c_secyear, year_total AS t_w_firstyear, year_total AS t_w_secyear, customer
WHERE (t_s_secyear.customer_id = t_s_firstyear.customer_id) AND (t_s_firstyear.customer_id = t_c_secyear.customer_id) AND (t_s_firstyear.customer_id = t_c_firstyear.customer_id) AND (t_s_firstyear.customer_id = t_w_firstyear.customer_id) AND (t_s_firstyear.customer_id = t_w_secyear.customer_id) AND (t_s_secyear.customer_id = customer.c_customer_id) AND (t_s_firstyear.sale_type = 's') AND (t_c_firstyear.sale_type = 'c') AND (t_w_firstyear.sale_type = 'w') AND (t_s_secyear.sale_type = 's') AND (t_c_secyear.sale_type = 'c') AND (t_w_secyear.sale_type = 'w') AND (t_s_firstyear.dyear = 2001) AND (t_s_secyear.dyear = (2001 + 1)) AND (t_c_firstyear.dyear = 2001) AND (t_c_secyear.dyear = (2001 + 1)) AND (t_w_firstyear.dyear = 2001) AND (t_w_secyear.dyear = (2001 + 1)) AND (t_s_firstyear.year_total > 0) AND (t_c_firstyear.year_total > 0) AND (t_w_firstyear.year_total > 0) AND (multiIf(t_c_firstyear.year_total > 0, t_c_secyear.year_total / t_c_firstyear.year_total, NULL) > multiIf(t_s_firstyear.year_total > 0, t_s_secyear.year_total / t_s_firstyear.year_total, NULL)) AND (multiIf(t_c_firstyear.year_total > 0, t_c_secyear.year_total / t_c_firstyear.year_total, NULL) > multiIf(t_w_firstyear.year_total > 0, t_w_secyear.year_total / t_w_firstyear.year_total, NULL))
ORDER BY t_s_secyear.customer_id ASC
LIMIT 100