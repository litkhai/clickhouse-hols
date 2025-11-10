--- 1) FIXED: 30 days -> INTERVAL 30 DAY
--- 2) Filtering joins rewritten to where join key IN ...
--- 3) Remove unnecessary joins after 1)
SELECT
    i_item_id,
    i_item_desc,
    i_category,
    i_class,
    i_current_price,
    sum(ws_ext_sales_price) AS itemrevenue,
    sum(ws_ext_sales_price * 100) / sum(sum(ws_ext_sales_price)) OVER (PARTITION BY i_class) AS revenueratio
FROM web_sales, item
WHERE (ws_item_sk = i_item_sk) AND (ws_item_sk IN (
    SELECT i_item_sk
    FROM item
    WHERE i_category IN ('Music', 'Women', 'Jewelry')
)) AND (i_category IN ('Music', 'Women', 'Jewelry')) AND (ws_sold_date_sk IN (
    SELECT d_date_sk
    FROM date_dim
    WHERE (CAST(d_date, 'date') >= CAST('1999-02-03', 'date')) AND (CAST(d_date, 'date') <= (CAST('1999-02-03', 'date') + toIntervalDay(30)))
))
GROUP BY
    i_item_id,
    i_item_desc,
    i_category,
    i_class,
    i_current_price
ORDER BY
    i_category ASC,
    i_class ASC,
    i_item_id ASC,
    i_item_desc ASC,
    revenueratio ASC
LIMIT 100