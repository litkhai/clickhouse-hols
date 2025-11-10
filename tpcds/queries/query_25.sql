WITH ss_pre as 
(
    SELECT ss_item_sk, ss_store_sk, ss_customer_sk, maxState(ss_net_profit) as store_sales_profit_state
    FROM store_sales
    WHERE ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy = 4 and d_year = 1999)
    GROUP BY ss_item_sk, ss_store_sk, ss_customer_sk
),
sr_pre as
(
    SELECT sr_item_sk, sr_customer_sk, maxState(sr_net_loss) as store_returns_loss_state
    FROM store_returns
    WHERE sr_returned_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy between 4 and 10 and d_year = 1999)
    GROUP BY sr_item_sk, sr_customer_sk
),
cs_pre as 
(
SELECT
    cs_item_sk,
    cs_bill_customer_sk,
    maxState(cs_net_profit) as catalog_sales_profit_state
FROM catalog_sales
WHERE cs_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_moy between 4 and 10 and d_year = 1999)
GROUP BY cs_item_sk, cs_bill_customer_sk
)
SELECT 
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
 ,maxMerge(store_sales_profit_state) as store_sales_profit
 ,maxMerge(store_returns_loss_state) as store_returns_loss
 ,maxMerge(catalog_sales_profit_state) as catalog_sales_profit
FROM ss_pre, sr_pre, cs_pre, item, store 
WHERE
    i_item_sk = ss_item_sk
    and s_store_sk = ss_store_sk
    and ss_customer_sk = sr_customer_sk
    and ss_item_sk = sr_item_sk
    and sr_customer_sk = cs_bill_customer_sk
    and sr_item_sk = cs_item_sk
group by
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
 order by
 i_item_id
 ,i_item_desc
 ,s_store_id
 ,s_store_name
LIMIT 100;