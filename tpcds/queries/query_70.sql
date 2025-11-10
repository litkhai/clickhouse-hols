--- 1) Filtering joins rewritten to where join key IN ...
--- 2) TODO: Fix grouping sets
SELECT
    sum(ss_net_profit) AS total_sum,
    s_state,
    s_county,
    grouping(s_state) + grouping(s_county) AS lochierarchy,
    rank() OVER (PARTITION BY grouping(s_state) + grouping(s_county), multiIf(grouping(s_county) = 0, s_state, NULL) ORDER BY sum(ss_net_profit) DESC) AS rank_within_parent
FROM store_sales, date_dim AS d1, store
WHERE ((d1.d_month_seq >= 1204) AND (d1.d_month_seq <= (1204 + 11))) AND (d1.d_date_sk = ss_sold_date_sk) AND (ss_sold_date_sk IN (
    SELECT d_date_sk
    FROM date_dim
    WHERE (d_month_seq >= 1204) AND (d_month_seq <= (1204 + 11))
)) AND (s_store_sk = ss_store_sk) AND (s_state IN (
    SELECT s_state
    FROM
    (
        SELECT
            s_state AS s_state,
            rank() OVER (PARTITION BY s_state ORDER BY sum(ss_net_profit) DESC) AS ranking
        FROM store_sales, store, date_dim
        WHERE ((d_month_seq >= 1204) AND (d_month_seq <= (1204 + 11))) AND (d_date_sk = ss_sold_date_sk) AND (ss_sold_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE (d_month_seq >= 1204) AND (d_month_seq <= (1204 + 11))
        )) AND (s_store_sk = ss_store_sk)
        GROUP BY s_state
    ) AS tmp1
    WHERE ranking <= 5
))
GROUP BY
    s_state,
    s_county
    WITH ROLLUP
ORDER BY
    lochierarchy DESC,
    multiIf(lochierarchy = 0, s_state, NULL) ASC,
    rank_within_parent ASC
LIMIT 100