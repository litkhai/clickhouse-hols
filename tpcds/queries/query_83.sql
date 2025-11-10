--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
WITH
    sr_items AS
    (
        SELECT
            i_item_id AS item_id,
            sum(sr_return_quantity) AS sr_item_qty
        FROM store_returns, item
        WHERE (sr_item_sk = i_item_sk) AND (sr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE d_week_seq IN (
                SELECT d_week_seq
                FROM date_dim
                WHERE d_date IN ('2002-01-07', '2002-09-06', '2002-11-09')
            )
        ))
        GROUP BY i_item_id
    ),
    cr_items AS
    (
        SELECT
            i_item_id AS item_id,
            sum(cr_return_quantity) AS cr_item_qty
        FROM catalog_returns, item
        WHERE (cr_item_sk = i_item_sk) AND (cr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE d_week_seq IN (
                SELECT d_week_seq
                FROM date_dim
                WHERE d_date IN ('2002-01-07', '2002-09-06', '2002-11-09')
            )
        ))
        GROUP BY i_item_id
    ),
    wr_items AS
    (
        SELECT
            i_item_id AS item_id,
            sum(wr_return_quantity) AS wr_item_qty
        FROM web_returns, item
        WHERE (wr_item_sk = i_item_sk) AND (wr_returned_date_sk IN (
            SELECT d_date_sk
            FROM date_dim
            WHERE d_week_seq IN (
                SELECT d_week_seq
                FROM date_dim
                WHERE d_date IN ('2002-01-07', '2002-09-06', '2002-11-09')
            )
        ))
        GROUP BY i_item_id
    )
SELECT
    sr_items.item_id,
    sr_item_qty,
    ((sr_item_qty / ((sr_item_qty + cr_item_qty) + wr_item_qty)) / 3.) * 100 AS sr_dev,
    cr_item_qty,
    ((cr_item_qty / ((sr_item_qty + cr_item_qty) + wr_item_qty)) / 3.) * 100 AS cr_dev,
    wr_item_qty,
    ((wr_item_qty / ((sr_item_qty + cr_item_qty) + wr_item_qty)) / 3.) * 100 AS wr_dev,
    ((sr_item_qty + cr_item_qty) + wr_item_qty) / 3. AS average
FROM sr_items, cr_items, wr_items
WHERE (sr_items.item_id = cr_items.item_id) AND (sr_items.item_id = wr_items.item_id)
ORDER BY
    sr_items.item_id ASC,
    sr_item_qty ASC
LIMIT 100