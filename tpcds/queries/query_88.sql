--- 1) Filtering joins rewritten to where join key IN ...
--- 2) Remove unnecessary joins after 1)
SELECT *
FROM
(
    SELECT count(*) AS h8_30_to_9
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 8 AND t_minute >= 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s1,
(
    SELECT count(*) AS h9_to_9_30
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 9 AND t_minute < 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s2,
(
    SELECT count(*) AS h9_30_to_10
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 9 AND t_minute >= 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s3,
(
    SELECT count(*) AS h10_to_10_30
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 10 AND t_minute < 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s4,
(
    SELECT count(*) AS h10_30_to_11
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 10 AND t_minute >= 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s5,
(
    SELECT count(*) AS h11_to_11_30
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 11 AND t_minute < 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s6,
(
    SELECT count(*) AS h11_30_to_12
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 11 AND t_minute >= 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s7,
(
    SELECT count(*) AS h12_to_12_30
    FROM store_sales
    WHERE 
        ss_sold_time_sk IN (SELECT t_time_sk FROM time_dim WHERE t_hour = 12 AND t_minute < 30) 
        AND ss_hdemo_sk IN (SELECT hd_demo_sk FROM household_demographics WHERE (((hd_dep_count = -1) AND (hd_vehicle_count <= (-1 + 2))) OR ((hd_dep_count = 1) AND (hd_vehicle_count <= (1 + 2))) OR ((hd_dep_count = 3) AND (hd_vehicle_count <= (3 + 2)))) ) 
        AND ss_store_sk IN (SELECT s_store_sk FROM store WHERE store.s_store_name = 'ese')
) AS s8