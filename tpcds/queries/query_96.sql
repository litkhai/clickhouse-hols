select count(*) 
from store_sales
where ss_sold_time_sk IN (SELECT t_time_sk from time_dim where time_dim.t_hour = 15 and time_dim.t_minute >= 30)
    and ss_hdemo_sk IN (SELECT hd_demo_sk from household_demographics where hd_dep_count = 2)
    and ss_store_sk IN (select s_store_sk from store where store.s_store_name = 'ese')
order by count(*)
LIMIT 100;