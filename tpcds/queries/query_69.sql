--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) Correlated subquery
SELECT
    cd_gender,
    cd_marital_status,
    cd_education_status,
    count(*) AS cnt1,
    cd_purchase_estimate,
    count(*) AS cnt2,
    cd_credit_rating,
    count(*) AS cnt3
FROM customer, customer_demographics
WHERE 
    c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_state IN ('NE', 'FL', 'KY')) 
    AND c_current_cdemo_sk = cd_demo_sk
AND c_customer_sk IN (
    SELECT ss_customer_sk 
    FROM store_sales
    WHERE ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 AND d_moy >= 1 AND d_moy <= (1 + 2))
) AND c_customer_sk NOT IN (
    SELECT ws_bill_customer_sk
    FROM web_sales
    WHERE ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999 AND d_moy >= 1 AND d_moy <= (1 + 2))
) AND c_customer_sk NOT IN (
    SELECT cs_ship_customer_sk
    FROM catalog_sales
    WHERE cs_sold_date_sk IN (SELECT d_date_sk  FROM date_dim WHERE  d_year = 1999 AND d_moy >= 1 AND d_moy <= (1 + 2))
)
GROUP BY
    cd_gender,
    cd_marital_status,
    cd_education_status,
    cd_purchase_estimate,
    cd_credit_rating
ORDER BY
    cd_gender ASC,
    cd_marital_status ASC,
    cd_education_status ASC,
    cd_purchase_estimate ASC,
    cd_credit_rating ASC
LIMIT 100