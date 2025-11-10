select ca_zip, ca_county, sum(ws_sales_price)
from web_sales, customer, customer_address
where ws_bill_customer_sk = c_customer_sk
    and c_current_addr_sk = ca_address_sk 
    and (substr(ca_zip,1,5) in ('85669', '86197','88274','83405','86475', '85392', '85460', '80348', '81792')
        or 
        ws_item_sk IN (
        SELECT i_item_sk FROM item
        where i_item_sk in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29)
        )
    )
    and ws_sold_date_sk IN (SELECT d_date_sk FROM date_dim WHERE d_qoy = 2 and d_year = 1999)
group by ca_zip, ca_county
order by ca_zip, ca_county
LIMIT 100;