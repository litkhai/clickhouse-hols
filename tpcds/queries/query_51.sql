
WITH web_v1 as (
select
  ws_item_sk item_sk, ws_sold_date_sk as date_sk,
  sum(sum(ws_sales_price))
      over (partition by ws_item_sk order by date_sk rows between unbounded preceding and current row) cume_sales
from web_sales
where ws_sold_date_sk IN (SELECT d_date_sk from date_dim WHERE d_month_seq between 1224 and 1224+11)
  and ws_item_sk is not NULL
group by ws_item_sk, date_sk),
store_v1 as (
select
  ss_item_sk item_sk, ss_sold_date_sk as date_sk,
  sum(sum(ss_sales_price))
      over (partition by ss_item_sk order by date_sk rows between unbounded preceding and current row) cume_sales
from store_sales
where ss_sold_date_sk IN (SELECT d_date_sk from date_dim WHERE d_month_seq between 1224 and 1224+11)
  and ss_item_sk is not NULL
group by ss_item_sk, date_sk)
select 
    item_sk
     ,d_date
     ,web_sales
     ,store_sales
     ,web_cumulative
     ,store_cumulative
from (select item_sk
     ,date_sk
     ,web_sales
     ,store_sales
     ,max(web_sales)
         over (partition by item_sk order by date_sk rows between unbounded preceding and current row) web_cumulative
     ,max(store_sales)
         over (partition by item_sk order by date_sk rows between unbounded preceding and current row) store_cumulative
     from (select case when web.item_sk is not null then web.item_sk else store.item_sk end item_sk
                 ,case when web.date_sk is not null then web.date_sk else store.date_sk end date_sk
                 ,web.cume_sales web_sales
                 ,store.cume_sales store_sales
           from web_v1 web full outer join store_v1 store on (web.item_sk = store.item_sk
                    and web.date_sk = store.date_sk)
)x )y, date_dim
where web_cumulative > store_cumulative 
and date_sk=d_date_sk
order by item_sk
        ,d_date
LIMIT 100;