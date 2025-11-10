--- 1) Correlated subquery
WITH FILTER AS
    (
        SELECT DISTINCT ss_customer_sk
        FROM store_sales
        WHERE ss_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_year = 2000) AND ((d_moy >= 2) AND (d_moy <= (2 + 3)))
        )
        INTERSECT
        (
            SELECT DISTINCT ws_bill_customer_sk
            FROM web_sales
            WHERE ws_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 2000) AND ((d_moy >= 2) AND (d_moy <= (2 + 3)))
            )
            UNION DISTINCT
            SELECT DISTINCT cs_ship_customer_sk
            FROM catalog_sales
            WHERE cs_sold_date_sk IN (
                SELECT d_date_sk
                FROM date_dim
                WHERE (d_year = 2000) AND ((d_moy >= 2) AND (d_moy <= (2 + 3)))
            )
        )
    )
SELECT
    cd_gender,
    cd_marital_status,
    cd_education_status,
    count(*) AS cnt1,
    cd_purchase_estimate,
    count(*) AS cnt2,
    cd_credit_rating,
    count(*) AS cnt3,
    cd_dep_count,
    count(*) AS cnt4,
    cd_dep_employed_count,
    count(*) AS cnt5,
    cd_dep_college_count,
    count(*) AS cnt6
FROM customer AS c, customer_demographics
WHERE (c_current_addr_sk IN (
    SELECT ca_address_sk
    FROM customer_address
    WHERE ca_county IN ('Lycoming County', 'Sheridan County', 'Kandiyohi County', 'Pike County', 'Greene County')
)) AND (cd_demo_sk = c.c_current_cdemo_sk) AND (c_customer_sk IN (FILTER))
GROUP BY
    cd_gender,
    cd_marital_status,
    cd_education_status,
    cd_purchase_estimate,
    cd_credit_rating,
    cd_dep_count,
    cd_dep_employed_count,
    cd_dep_college_count
ORDER BY
    cd_gender ASC,
    cd_marital_status ASC,
    cd_education_status ASC,
    cd_purchase_estimate ASC,
    cd_credit_rating ASC,
    cd_dep_count ASC,
    cd_dep_employed_count ASC,
    cd_dep_college_count ASC
LIMIT 100