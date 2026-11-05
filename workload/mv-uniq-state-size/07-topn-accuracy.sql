-- 07-topn-accuracy.sql: does the state function change the answer?

-- (a) The exact Top 10 and Bottom 10 for the last hour (uniqExact over the raw rows).
SELECT
    arraySlice(arraySort(t -> (-toInt64(t.2), t.1), groupArray((page, users))), 1, 10) AS top10_page_users,
    arraySlice(arraySort(t -> (toInt64(t.2), t.1), groupArrayIf((page, users), events >= 1000)), 1, 10) AS bottom10_page_users
FROM
(
    SELECT page, uniqExact(user_u64) AS users, count() AS events
    FROM mv_uniq.events
    WHERE ts >= '2026-11-01 02:00:00'
    GROUP BY page
);

-- (b) Per page over the last hour, every state column of the 1-minute rollup against uniqExact(UInt64):
-- relative error, and how many of the exact Top 10 / Bottom 10 pages it returns (and in the same order).
WITH per_page AS
(
    SELECT page, sum(events) AS events,
           uniqExactMerge(u_exact_u64) AS exact,
           [uniqMerge(u_uniq_str), uniqMerge(u_uniq_u64), uniqMerge(u_uniq_u32),
            uniqCombinedMerge(u_comb_u64), uniqCombinedMerge(12)(u_comb12_u64), uniqHLL12Merge(u_hll12_u64),
            uniqExactMerge(u_exact_str), uniqExactMerge(u_exact_u32)] AS ests
    FROM mv_uniq.rollup_1m
    WHERE bucket >= '2026-11-01 02:00:00'
    GROUP BY page
)
SELECT fn, pages, mean_err_pct, max_err_pct,
       top10_same_pages, top10_same_order, bottom10_same_pages, bottom10_same_order
FROM
(
SELECT
    fn,
    count() AS pages,
    round(avg(abs(est - exact) / exact) * 100, 3) AS mean_err_pct,
    round(max(abs(est - exact) / exact) * 100, 3) AS max_err_pct,
    arraySlice(arrayMap(t -> t.2, arraySort(t -> (-toInt64(t.1), t.2), groupArray((est, page)))), 1, 10)   AS top_est,
    arraySlice(arrayMap(t -> t.2, arraySort(t -> (-toInt64(t.1), t.2), groupArray((exact, page)))), 1, 10) AS top_exact,
    arraySlice(arrayMap(t -> t.2, arraySort(t -> (toInt64(t.1), t.2), groupArrayIf((est, page), events >= 1000))), 1, 10)   AS bottom_est,
    arraySlice(arrayMap(t -> t.2, arraySort(t -> (toInt64(t.1), t.2), groupArrayIf((exact, page), events >= 1000))), 1, 10) AS bottom_exact,
    length(arrayIntersect(top_est, top_exact))       AS top10_same_pages,
    top_est = top_exact                              AS top10_same_order,
    length(arrayIntersect(bottom_est, bottom_exact)) AS bottom10_same_pages,
    bottom_est = bottom_exact                        AS bottom10_same_order
FROM per_page
ARRAY JOIN ['uniq(String)', 'uniq(UInt64)', 'uniq(UInt32)', 'uniqCombined(UInt64)', 'uniqCombined(12)(UInt64)',
            'uniqHLL12(UInt64)', 'uniqExact(String)', 'uniqExact(UInt32)'] AS fn, ests AS est
GROUP BY fn
ORDER BY indexOf(['uniq(String)', 'uniq(UInt64)', 'uniq(UInt32)', 'uniqCombined(UInt64)', 'uniqCombined(12)(UInt64)',
                  'uniqHLL12(UInt64)', 'uniqExact(String)', 'uniqExact(UInt32)'], fn)
);

-- (c) Error per rollup row (one group): the approximate states against uniqExact(UInt64) in the same row.
SELECT level, fn,
       round(avg(abs(est - exact) / exact) * 100, 3)             AS mean_err_pct,
       round(quantileExact(0.99)(abs(est - exact) / exact) * 100, 3)  AS p99_err_pct,
       round(max(abs(est - exact) / exact) * 100, 3)             AS max_err_pct,
       round(countIf(est != exact) * 100 / count(), 2)           AS inexact_groups_pct
FROM
(
    SELECT 'rollup_1m' AS level, uniqExactMerge(u_exact_u64) AS exact,
           [uniqMerge(u_uniq_u64), uniqCombinedMerge(u_comb_u64), uniqCombinedMerge(12)(u_comb12_u64), uniqHLL12Merge(u_hll12_u64)] AS ests
    FROM mv_uniq.rollup_1m
    GROUP BY bucket, kind, page
    UNION ALL
    SELECT 'rollup_10m', uniqExactMerge(u_exact_u64),
           [uniqMerge(u_uniq_u64), uniqCombinedMerge(u_comb_u64), uniqCombinedMerge(12)(u_comb12_u64), uniqHLL12Merge(u_hll12_u64)]
    FROM mv_uniq.rollup_10m
    GROUP BY bucket, kind, page
)
ARRAY JOIN ['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12'] AS fn, ests AS est
GROUP BY level, fn
ORDER BY level, indexOf(['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12'], fn);
