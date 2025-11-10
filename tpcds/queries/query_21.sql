SELECT
    *
FROM(
    SELECT 
        w_warehouse_name,
        i_item_id,
        Sum(CASE WHEN (CAST(d_date AS DATE) < CAST ('2000-05-13' AS DATE)) THEN inv_quantity_on_hand ELSE 0 END) AS inv_before,
        Sum(CASE WHEN (CAST(d_date AS DATE) >= CAST ('2000-05-13' AS DATE)) THEN inv_quantity_on_hand ELSE 0 END) AS inv_after
    FROM  
        inventory ,
        warehouse ,
        item,
        date_dim
    WHERE
    inv_date_sk IN 
        ( SELECT  d_date_sk FROM date_dim 
          WHERE CAST(d_date AS DATE) BETWEEN 
            (cast ('2000-04-13' AS DATE)) AND
            (cast ('2000-06-13' AS DATE)))
    AND inv_date_sk = d_date_sk
    AND i_current_price BETWEEN 0.99 AND 1.49
    AND inv_item_sk IN (SELECT i_item_sk FROM item WHERE i_current_price BETWEEN 0.99 AND 1.49)
    AND i_item_sk = inv_item_sk
    AND inv_warehouse_sk = w_warehouse_sk
    GROUP BY w_warehouse_name,i_item_id
    ) x
WHERE (
      CASE
               WHEN inv_before > 0 THEN inv_after / inv_before
               ELSE NULL
      END) BETWEEN 2.0/3.0 AND      3.0/2.0
ORDER BY w_warehouse_name, i_item_id
LIMIT 100;