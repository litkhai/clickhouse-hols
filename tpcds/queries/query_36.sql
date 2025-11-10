with results as
 (select 
    sum(ss_net_profit) as ss_net_profit_,
    sum(ss_ext_sales_price) as ss_ext_sales_price_,
    sum(ss_net_profit)/sum(ss_ext_sales_price) as gross_margin
   ,i_category
   ,i_class
   ,0 as g_category, 0 as g_class
 from
    store_sales
   ,item
 where
    ss_sold_date_sk in (select d_date_sk from date_dim where d_year = 1999)
    and i_item_sk  = ss_item_sk 
    and ss_store_sk IN (SELECT s_store_sk from store where s_state in ('OH',
'NY',
'SD',
'NM',
'FL',
'AL',
'WA',
'IN'))
 group by i_category,i_class)
 ,
 results_rollup as
 (select gross_margin ,i_category ,i_class,0 as t_category, 0 as t_class, 0 as lochierarchy from results
 union all
 select sum(ss_net_profit_)/sum(ss_ext_sales_price_) as gross_margin,
   i_category, NULL AS i_class, 0 as t_category, 1 as t_class, 1 as lochierarchy from results group by i_category
 union all
 select sum(ss_net_profit_)/sum(ss_ext_sales_price_) as gross_margin,
   NULL AS i_category ,NULL AS i_class, 1 as t_category, 1 as t_class, 2 as lochierarchy from results)
  select
  gross_margin ,i_category ,i_class, lochierarchy,rank() over (
   partition by lochierarchy, case when t_class = 0 then i_category end 
   order by gross_margin asc) as rank_within_parent
 from results_rollup
 order by
   lochierarchy desc
  ,case when lochierarchy = 0 then i_category end
  ,rank_within_parent
  LIMIT 100;