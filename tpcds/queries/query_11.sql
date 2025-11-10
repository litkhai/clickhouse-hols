--- 1) FIXED 0. to 0 as 0. parsed as float and did not convert to Decimal. https://github.com/ClickHouse/ClickHouse/issues/5690
--- 2) Aggregation performed before joins by joining key
--- 3) Filtering joins rewritten to where join key IN ...
WITH year_total AS
    (
        SELECT
            c_customer_id AS customer_id,
            c_first_name AS customer_first_name,
            c_last_name AS customer_last_name,
            c_preferred_cust_flag AS customer_preferred_cust_flag,
            c_birth_country AS customer_birth_country,
            c_login AS customer_login,
            c_email_address AS customer_email_address,
            d_year AS dyear,
            sum(year_total) AS year_total,
            's' AS sale_type
        FROM customer,
        (
            SELECT
                ss_customer_sk,
                d_year,
                sum(ss_ext_list_price - ss_ext_discount_amt) AS year_total
            FROM store_sales, date_dim
            WHERE (ss_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 1999) OR (d_year = (1999 + 1))
            )) AND (ss_sold_date_sk = d_date_sk)
            GROUP BY
                ss_customer_sk,
                d_year
        ) AS right
        WHERE c_customer_sk = ss_customer_sk
        GROUP BY
            c_customer_id,
            c_first_name,
            c_last_name,
            c_preferred_cust_flag,
            c_birth_country,
            c_login,
            c_email_address,
            d_year
        UNION ALL
        SELECT
            c_customer_id AS customer_id,
            c_first_name AS customer_first_name,
            c_last_name AS customer_last_name,
            c_preferred_cust_flag AS customer_preferred_cust_flag,
            c_birth_country AS customer_birth_country,
            c_login AS customer_login,
            c_email_address AS customer_email_address,
            d_year AS dyear,
            sum(year_total) AS year_total,
            'w' AS sale_type
        FROM customer,
        (
            SELECT
                ws_bill_customer_sk,
                d_year,
                sum(ws_ext_list_price - ws_ext_discount_amt) AS year_total
            FROM web_sales, date_dim
            WHERE (ws_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 1999) OR (d_year = (1999 + 1))
            )) AND (ws_sold_date_sk = d_date_sk)
            GROUP BY
                ws_bill_customer_sk,
                d_year
        ) AS right
        WHERE c_customer_sk = ws_bill_customer_sk
        GROUP BY
            c_customer_id,
            c_first_name,
            c_last_name,
            c_preferred_cust_flag,
            c_birth_country,
            c_login,
            c_email_address,
            d_year
    )
SELECT
    t_s_secyear.customer_id,
    t_s_secyear.customer_first_name,
    t_s_secyear.customer_last_name,
    t_s_secyear.customer_preferred_cust_flag
FROM year_total AS t_s_firstyear, year_total AS t_s_secyear, year_total AS t_w_firstyear, year_total AS t_w_secyear
WHERE (t_s_secyear.customer_id = t_s_firstyear.customer_id) AND (t_s_firstyear.customer_id = t_w_secyear.customer_id) AND (t_s_firstyear.customer_id = t_w_firstyear.customer_id) AND (t_s_firstyear.sale_type = 's') AND (t_w_firstyear.sale_type = 'w') AND (t_s_secyear.sale_type = 's') AND (t_w_secyear.sale_type = 'w') AND (t_s_firstyear.dyear = 1999) AND (t_s_secyear.dyear = (1999 + 1)) AND (t_w_firstyear.dyear = 1999) AND (t_w_secyear.dyear = (1999 + 1)) AND (t_s_firstyear.year_total > 0) AND (t_w_firstyear.year_total > 0) AND (multiIf(t_w_firstyear.year_total > 0, t_w_secyear.year_total / t_w_firstyear.year_total, 0) > multiIf(t_s_firstyear.year_total > 0, t_s_secyear.year_total / t_s_firstyear.year_total, 0))
ORDER BY
    t_s_secyear.customer_id ASC,
    t_s_secyear.customer_first_name ASC,
    t_s_secyear.customer_last_name ASC,
    t_s_secyear.customer_preferred_cust_flag ASC
LIMIT 100
SETTINGS join_algorithm = 'parallel_hash'