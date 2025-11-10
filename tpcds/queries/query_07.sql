--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
SELECT
    i_item_id,
    avg(ss_quantity) AS agg1,
    avg(ss_list_price) AS agg2,
    avg(ss_coupon_amt) AS agg3,
    avg(ss_sales_price) AS agg4
FROM store_sales, item
WHERE (ss_sold_date_sk IN (
    SELECT d_date_sk
    FROM date_dim
    WHERE d_year = 1998
)) AND (ss_item_sk = i_item_sk) AND (ss_cdemo_sk IN (
    SELECT cd_demo_sk
    FROM customer_demographics
    WHERE (cd_gender = 'F') AND (cd_marital_status = 'W') AND (cd_education_status = '2 yr Degree')
)) AND (ss_promo_sk IN (
    SELECT p_promo_sk
    FROM promotion
    WHERE (p_channel_email = 'N') OR (p_channel_event = 'N')
))
GROUP BY i_item_id
ORDER BY i_item_id ASC
LIMIT 100