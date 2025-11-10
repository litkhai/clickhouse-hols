WITH preaggr_ss as 
(
select
    ss_ticket_number,
    ss_store_sk,
    ss_item_sk,
    ss_customer_sk,
    sum(ss_ext_sales_price) netpaid_intermediate
FROM store_sales
WHERE
  ss_item_sk IN (SELECT i_item_sk FROM item WHERE i_color='papaya')
  and ss_store_sk IN (SELECT s_store_sk FROM store WHERE s_market_id=5)
GROUP BY 
    ss_ticket_number,
    ss_store_sk,
    ss_item_sk,
    ss_customer_sk
),
ssales as 
(
select 
   c_last_name
  ,c_first_name
  ,s_store_name
  ,ca_state
  ,s_state
  ,i_color
  ,i_current_price
  ,i_manager_id
  ,i_units
  ,i_size
  ,sum(netpaid_intermediate) netpaid
FROM 
    store_returns
    ,preaggr_ss
    ,item
    ,store
    ,customer
    ,customer_address

where ss_ticket_number = sr_ticket_number
  and ss_item_sk = sr_item_sk
  and ss_customer_sk = c_customer_sk
  and ss_item_sk = i_item_sk
  and ss_store_sk = s_store_sk
  and c_current_addr_sk = ca_address_sk
  and c_birth_country <> upper(ca_country)
  and s_zip = ca_zip
  and s_market_id=5
group by c_last_name
        ,c_first_name
        ,s_store_name
        ,ca_state
        ,s_state
        ,i_color
        ,i_current_price
        ,i_manager_id
        ,i_units
        ,i_size
)
select c_last_name
      ,c_first_name
      ,s_store_name
      ,sum(netpaid) paid
from ssales
where i_color = 'papaya'
group by c_last_name
        ,c_first_name
        ,s_store_name
having sum(netpaid) > (select 0.05*avg(netpaid)
                                 from ssales)
order by c_last_name
        ,c_first_name
        ,s_store_name
;