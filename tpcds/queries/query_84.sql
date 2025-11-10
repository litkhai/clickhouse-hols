--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
SELECT
    c_customer_id AS customer_id,
    concat(coalesce(c_last_name, ''), ', ', coalesce(c_first_name, '')) AS customername
FROM customer, customer_demographics, store_returns
WHERE (c_current_addr_sk IN (
    SELECT ca_address_sk
    FROM customer_address
    WHERE ca_city = 'Union'
)) AND (cd_demo_sk = c_current_cdemo_sk) AND (c_current_hdemo_sk IN (
    SELECT hd_demo_sk
    FROM household_demographics
    WHERE hd_income_band_sk IN (
        SELECT ib_income_band_sk
        FROM income_band
        WHERE (ib_lower_bound >= 14931) AND (ib_upper_bound <= (14931 + 50000))
    )
)) AND (sr_cdemo_sk = cd_demo_sk)
ORDER BY c_customer_id ASC
LIMIT 100
