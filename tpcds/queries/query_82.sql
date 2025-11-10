--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) FIXED: 30 days -> INTERVAL 30 DAY
SELECT
    i_item_id,
    i_item_desc,
    i_current_price
FROM item, store_sales
WHERE ((i_current_price >= 2) AND (i_current_price <= (2 + 30))) AND (i_manufact_id IN (910, 476, 598, 346)) AND (i_item_sk IN (
    SELECT inv_item_sk
    FROM inventory
    WHERE ((inv_quantity_on_hand >= 100) AND (inv_quantity_on_hand <= 500)) AND (inv_date_sk IN (
        SELECT d_date_sk
        FROM date_dim
        WHERE (d_date >= CAST('1998-03-28', 'date')) AND (d_date <= (CAST('1998-03-28', 'date') + toIntervalDay(60)))
    ))
)) AND (ss_item_sk = i_item_sk)
GROUP BY
    i_item_id,
    i_item_desc,
    i_current_price
ORDER BY i_item_id ASC
LIMIT 100