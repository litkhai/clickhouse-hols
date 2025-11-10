with t as 
(select count(*) as item_cnt, i_manufact 
 from item
 where (
        ((i_category = 'Women' and 
        (i_color = 'aquamarine' or i_color = 'navy') and 
        (i_units = 'Pallet' or i_units = 'Dozen') and
        (i_size = 'extra large' or i_size = 'small')
        ) or
        (i_category = 'Women' and
        (i_color = 'burlywood' or i_color = 'black') and
        (i_units = 'Tbl' or i_units = 'Bundle') and
        (i_size = 'petite' or i_size = 'economy')
        ) or
        (i_category = 'Men' and
        (i_color = 'orchid' or i_color = 'brown') and
        (i_units = 'Ounce' or i_units = 'Cup') and
        (i_size = 'extra large' or i_size = 'small')
        ) or
        (i_category = 'Men' and
        (i_color = 'chocolate' or i_color = 'maroon') and
        (i_units = 'Tsp' or i_units = 'Gross') and
        (i_size = 'petite' or i_size = 'economy')
        ))) or
       (
        ((i_category = 'Women' and 
        (i_color = 'moccasin' or i_color = 'antique') and 
        (i_units = 'Box' or i_units = 'Lb') and
        (i_size = 'extra large' or i_size = 'small')
        ) or
        (i_category = 'Women' and
        (i_color = 'blush' or i_color = 'dark') and
        (i_units = 'Carton' or i_units = 'Oz') and
        (i_size = 'petite' or i_size = 'economy')
        ) or
        (i_category = 'Men' and
        (i_color = 'deep' or i_color = 'firebrick') and
        (i_units = 'Each' or i_units = 'Gram') and
        (i_size = 'extra large' or i_size = 'small')
        ) or
        (i_category = 'Men' and
        (i_color = 'almond' or i_color = 'honeydew') and
        (i_units = 'Case' or i_units = 'Unknown') and
        (i_size = 'petite' or i_size = 'economy')
        )))
group by i_manufact
having item_cnt>0
)
 select distinct(i_product_name)
 from item i1, t
 where i_manufact_id between 771 and 771+40
 and i1.i_manufact = t.i_manufact
 and t.item_cnt > 0
 order by i_product_name
 limit 100;