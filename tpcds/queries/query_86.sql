--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) FIXED:  UNKNOWN_IDENTIFIER / NOT_FOUND_COLUMN_IN_BLOCK https://github.com/ClickHouse/ClickHouse/issues/44490
SELECT
    sum(ws_net_paid) AS total_sum,
    i_category,
    i_class,
    grouping(i_category) + grouping(i_class) AS lochierarchy,
    rank() OVER (PARTITION BY grouping(i_category) + grouping(i_class), multiIf(grouping(i_class) = 0, i_category, NULL) ORDER BY sum(ws_net_paid) DESC) AS rank_within_parent
FROM web_sales, item
WHERE
    ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_month_seq >= 1186 AND d_month_seq <= (1186 + 11))
    AND (i_item_sk = ws_item_sk)
GROUP BY
    i_category,
    i_class
    WITH ROLLUP
ORDER BY
    lochierarchy DESC,
    i_category ASC,
    rank_within_parent ASC
LIMIT 100