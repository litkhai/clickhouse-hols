--- 1) We had to aggregate prices for each day before we join the week number and day of the week.
--- 2) sum(multiIf(cond, column, NULL)) -> sumIf(cond, preaggredated_sum() ) as NULLs are not used
WITH
    wscs AS
    (
        SELECT
            sold_date_sk,
            sales_price
        FROM
        (
            SELECT
                ws_sold_date_sk AS sold_date_sk,
                ws_ext_sales_price AS sales_price
            FROM web_sales
        )
        UNION ALL
        SELECT
            cs_sold_date_sk AS sold_date_sk,
            cs_ext_sales_price AS sales_price
        FROM catalog_sales
    ),
    wswscs_mid AS
    (
        SELECT
            sold_date_sk,
            sum_sales_price,
            d_day_name,
            d_week_seq
        FROM
        (
            SELECT
                sold_date_sk,
                sum(sales_price) AS sum_sales_price
            FROM wscs
            GROUP BY sold_date_sk
        ) AS t_agg
        ANY LEFT JOIN date_dim ON t_agg.sold_date_sk = date_dim.d_date_sk
    ),
    wswscs AS
    (
        SELECT
            d_week_seq,
            sumIf(sum_sales_price, d_day_name = 'Sunday') AS sun_sales,
            sumIf(sum_sales_price, d_day_name = 'Monday') AS mon_sales,
            sumIf(sum_sales_price, d_day_name = 'Tuesday') AS tue_sales,
            sumIf(sum_sales_price, d_day_name = 'Wednesday') AS wed_sales,
            sumIf(sum_sales_price, d_day_name = 'Thursday') AS thu_sales,
            sumIf(sum_sales_price, d_day_name = 'Friday') AS fri_sales,
            sumIf(sum_sales_price, d_day_name = 'Saturday') AS sat_sales
        FROM wswscs_mid
        GROUP BY d_week_seq
    )
SELECT
    d_week_seq1,
    round(sun_sales1 / sun_sales2, 2),
    round(mon_sales1 / mon_sales2, 2),
    round(tue_sales1 / tue_sales2, 2),
    round(wed_sales1 / wed_sales2, 2),
    round(thu_sales1 / thu_sales2, 2),
    round(fri_sales1 / fri_sales2, 2),
    round(sat_sales1 / sat_sales2, 2)
FROM
(
    SELECT
        wswscs.d_week_seq AS d_week_seq1,
        sun_sales AS sun_sales1,
        mon_sales AS mon_sales1,
        tue_sales AS tue_sales1,
        wed_sales AS wed_sales1,
        thu_sales AS thu_sales1,
        fri_sales AS fri_sales1,
        sat_sales AS sat_sales1
    FROM wswscs, date_dim
    WHERE (date_dim.d_week_seq = wswscs.d_week_seq) AND (d_year = 1998)
) AS y,
(
    SELECT
        wswscs.d_week_seq AS d_week_seq2,
        sun_sales AS sun_sales2,
        mon_sales AS mon_sales2,
        tue_sales AS tue_sales2,
        wed_sales AS wed_sales2,
        thu_sales AS thu_sales2,
        fri_sales AS fri_sales2,
        sat_sales AS sat_sales2
    FROM wswscs, date_dim
    WHERE (date_dim.d_week_seq = wswscs.d_week_seq) AND (d_year = (1998 + 1))
) AS z
WHERE d_week_seq1 = (d_week_seq2 - 53)
ORDER BY d_week_seq1 ASC