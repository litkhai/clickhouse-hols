--- 1) Correlated subquery
--- 2) Filtering joins rewritten to where join key IN ...
SELECT
    a.ca_state AS state,
    count() AS cnt
FROM
(
    SELECT s.ss_customer_sk AS ss_customer_sk
    FROM store_sales AS s, item AS i,
    (
        SELECT
            i_category,
            1.2 * avg(i_current_price) AS avg_price
        FROM item
        GROUP BY i_category
    ) AS t
    WHERE (s.ss_sold_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE (d_year = 2001) AND (d_moy = 2)
    )) AND (s.ss_item_sk = i.i_item_sk) AND (t.i_category = i.i_category) AND (i.i_current_price > t.avg_price)
) AS left, customer AS c, customer_address AS a
WHERE (left.ss_customer_sk = c.c_customer_sk) AND (a.ca_address_sk = c.c_current_addr_sk)
GROUP BY a.ca_state
HAVING count(*) >= 10
ORDER BY
    cnt ASC,
    a.ca_state ASC
LIMIT 100