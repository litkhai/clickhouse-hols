--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
--- 3) ILLEGAL_DIVISION works on tpcds1000+
SELECT CAST(amc, 'decimal(15, 4)') / CAST(pmc, 'decimal(15, 4)') AS am_pm_ratio
FROM
(
    SELECT count(*) AS amc
    FROM web_sales
    WHERE ws_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour >= 8 AND t_hour <= (8 + 1))
    AND ws_ship_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE hd_dep_count = 1)
    AND ws_web_page_sk IN (SELECT wp_web_page_sk FROM web_page WHERE wp_char_count >= 5000 AND wp_char_count <= 5200)
) AS at,
(
    SELECT count(*) AS pmc
    FROM web_sales
    WHERE ws_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour >= 19 AND t_hour <= (19 + 1))
    AND ws_ship_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE hd_dep_count = 1)
    AND ws_web_page_sk IN (SELECT wp_web_page_sk FROM web_page WHERE wp_char_count >= 5000 AND wp_char_count <= 5200)
) AS pt
ORDER BY am_pm_ratio ASC
LIMIT 1