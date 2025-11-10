with sum_day as 
(
select sum(ss_sales_price) as sum_ss, ss_sold_date_sk, ss_store_sk
from store_sales
where 
    ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_year = 1999)
    and ss_store_sk IN (SELECT s_store_sk FROM store WHERE s_gmt_offset = -5)
group by ss_sold_date_sk, ss_store_sk
)
select s_store_name, s_store_id,
        sum(case when (d_day_name='Sunday') then sum_ss else null end) sun_sales,
        sum(case when (d_day_name='Monday') then sum_ss else null end) mon_sales,
        sum(case when (d_day_name='Tuesday') then sum_ss else  null end) tue_sales,
        sum(case when (d_day_name='Wednesday') then sum_ss else null end) wed_sales,
        sum(case when (d_day_name='Thursday') then sum_ss else null end) thu_sales,
        sum(case when (d_day_name='Friday') then sum_ss else null end) fri_sales,
        sum(case when (d_day_name='Saturday') then sum_ss else null end) sat_sales
from
    sum_day, store, date_dim
where 
    d_date_sk = ss_sold_date_sk and
    s_store_sk = ss_store_sk and
    s_gmt_offset = -5
 group by s_store_name, s_store_id
 order by s_store_name, s_store_id,sun_sales,mon_sales,tue_sales,wed_sales,thu_sales,fri_sales,sat_sales; 
