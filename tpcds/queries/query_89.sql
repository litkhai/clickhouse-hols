--- 1) Filtering joins rewritten to where join key IN ...
SELECT *
FROM
(
    SELECT
        i_category,
        i_class,
        i_brand,
        s_store_name,
        s_company_name,
        d_moy,
        sum(ss_sales_price) AS sum_sales,
        avg(sum(ss_sales_price)) OVER (PARTITION BY i_category, i_brand, s_store_name, s_company_name) AS avg_monthly_sales
    FROM item, store_sales, date_dim, store
    WHERE 
        ss_item_sk = i_item_sk
        AND ss_item_sk IN (SELECT i_item_sk FROM item WHERE (((i_category IN ('Music', 'Electronics', 'Men')) AND (i_class IN ('classical', 'monitors', 'sports-apparel'))) OR ((i_category IN ('Shoes', 'Jewelry', 'Home')) AND (i_class IN ('mens', 'pendants', 'decor')))))
        AND (((i_category IN ('Music', 'Electronics', 'Men')) AND (i_class IN ('classical', 'monitors', 'sports-apparel'))) OR ((i_category IN ('Shoes', 'Jewelry', 'Home')) AND (i_class IN ('mens', 'pendants', 'decor')))) 
        AND ss_sold_date_sk = d_date_sk
        AND (ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 2001))
        AND (d_year IN (2001))
        AND (ss_store_sk = s_store_sk) 
    GROUP BY
        i_category,
        i_class,
        i_brand,
        s_store_name,
        s_company_name,
        d_moy
) AS tmp1
WHERE multiIf(avg_monthly_sales != 0, abs(sum_sales - avg_monthly_sales) / avg_monthly_sales, NULL) > 0.1
ORDER BY
    sum_sales - avg_monthly_sales ASC,
    s_store_name ASC
LIMIT 100