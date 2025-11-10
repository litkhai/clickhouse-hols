--- 1) Correlated subquery
--- 2) Filtered data from large table by s_store_sk, which is filtered in the end of the query
--- + AND sr_store_sk IN (SELECT s_store_sk FROM store WHERE s_state='TN')
WITH
    customer_total_return AS
    (
        SELECT
            sr_customer_sk AS ctr_customer_sk,
            sr_store_sk AS ctr_store_sk,
            sum(sr_fee) AS ctr_total_return
        FROM store_returns
        WHERE sr_returned_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2000)
        GROUP BY
            sr_customer_sk,
            sr_store_sk
    ),
    high_return AS
    (
        SELECT
            ctr_store_sk,
            Avg(ctr_total_return) * 1.2 AS return_limit
        FROM customer_total_return AS ctr2
        GROUP BY ctr_store_sk
    )
SELECT c_customer_id
FROM customer_total_return AS ctr1, store, customer, high_return
WHERE (ctr1.ctr_total_return > high_return.return_limit) AND (s_store_sk = ctr1.ctr_store_sk) AND (s_state = 'NM') AND (ctr1.ctr_customer_sk = c_customer_sk) AND (ctr1.ctr_store_sk = high_return.ctr_store_sk)
ORDER BY c_customer_id ASC
LIMIT 100