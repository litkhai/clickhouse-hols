WITH sales as 
(select 
    ss_store_sk,
    ss_sold_date_sk,
    sum(ss_sales_price) daily_sales
 from store_sales
 where ss_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_week_seq IN (SELECT d_week_seq FROM date_dim WHERE d_month_seq between 1200 and 1200 + 11 OR d_month_seq between 1200+ 12 and 1200 + 23))
 group by ss_store_sk,ss_sold_date_sk 
),
wss as 
(
    select
    d_week_seq,
    ss_store_sk,
    sum(case when (d_day_name='Sunday') then daily_sales else null end) sun_sales,
    sum(case when (d_day_name='Monday') then daily_sales else null end) mon_sales,
    sum(case when (d_day_name='Tuesday') then daily_sales else  null end) tue_sales,
    sum(case when (d_day_name='Wednesday') then daily_sales else null end) wed_sales,
    sum(case when (d_day_name='Thursday') then daily_sales else null end) thu_sales,
    sum(case when (d_day_name='Friday') then daily_sales else null end) fri_sales,
    sum(case when (d_day_name='Saturday') then daily_sales else null end) sat_sales
    FROM sales, date_dim
    WHERE ss_sold_date_sk=d_date_sk
    group by d_week_seq,ss_store_sk
)
select s_store_name1,s_store_id1,d_week_seq1
       ,sun_sales1/sun_sales2,mon_sales1/mon_sales2
       ,tue_sales1/tue_sales2,wed_sales1/wed_sales2,thu_sales1/thu_sales2
       ,fri_sales1/fri_sales2,sat_sales1/sat_sales2
 from
 (select s_store_name s_store_name1,wss.d_week_seq d_week_seq1
        ,s_store_id s_store_id1,sun_sales sun_sales1
        ,mon_sales mon_sales1,tue_sales tue_sales1
        ,wed_sales wed_sales1,thu_sales thu_sales1
        ,fri_sales fri_sales1,sat_sales sat_sales1
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and 
        d_month_seq between 1200 and 1200 + 11) y,
 (select s_store_name s_store_name2,wss.d_week_seq d_week_seq2
        ,s_store_id s_store_id2,sun_sales sun_sales2
        ,mon_sales mon_sales2,tue_sales tue_sales2
        ,wed_sales wed_sales2,thu_sales thu_sales2
        ,fri_sales fri_sales2,sat_sales sat_sales2
  from wss,store,date_dim d
  where d.d_week_seq = wss.d_week_seq and
        ss_store_sk = s_store_sk and 
        d_month_seq between 1200+ 12 and 1200 + 23) x
 where s_store_id1=s_store_id2
   and d_week_seq1=d_week_seq2-52
 order by s_store_name1,s_store_id1,d_week_seq1
LIMIT 100;