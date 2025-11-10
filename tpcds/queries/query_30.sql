with customer_total_return as
 (select wr_returning_customer_sk as ctr_customer_sk
        ,ca_state as ctr_state, 
         sum(wr_return_amt) as ctr_total_return
 from web_returns
     ,customer_address
 where wr_returned_date_sk IN (SELECT d_date_sk FROM date_dim where d_year = 1999)
   and wr_returning_addr_sk = ca_address_sk 
 group by wr_returning_customer_sk
         ,ca_state),
 avg_total_return_per_state as
(
    SELECT
    ctr_state, avg(ctr_total_return) as avg_ctr_total_return
    FROM customer_total_return
    GROUP BY ctr_state
)
 select c_customer_id,c_salutation,c_first_name,c_last_name,c_preferred_cust_flag
       ,c_birth_day,c_birth_month,c_birth_year,c_birth_country,c_login,c_email_address
       ,c_last_review_date,ctr_total_return
 from customer_total_return ctr1
      ,avg_total_return_per_state
      ,customer
 where ctr1.ctr_total_return > 1.2*avg_ctr_total_return 
       and ctr1.ctr_state = avg_total_return_per_state.ctr_state
       and c_current_addr_sk IN (SELECT ca_address_sk FROM customer_address WHERE ca_state = 'MN')
       and ctr1.ctr_customer_sk = c_customer_sk
 order by c_customer_id,c_salutation,c_first_name,c_last_name,c_preferred_cust_flag
                  ,c_birth_day,c_birth_month,c_birth_year,c_birth_country,c_login,c_email_address
                  ,c_last_review_date,ctr_total_return
LIMIT 100;