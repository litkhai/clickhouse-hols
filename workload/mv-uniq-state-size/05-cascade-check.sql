-- 05-cascade-check.sql: is the 10-minute rollup built from the 1-minute rollup right?

-- Positive check: the cascaded 10-minute rollup against 10-minute groups computed straight from the
-- raw rows. Both sides must have the same groups and events, uniqExact and uniq must match exactly.
-- The approximate functions are compared too: a merged state need not give the same estimate as
-- one built from all rows at once.
SELECT
    count()                                   AS groups,
    countIf(r.bucket_ok = 0 OR d.bucket_ok = 0) AS one_side_only,
    countIf(r.events != d.events)             AS events_diff,
    countIf(r.exact != d.exact)               AS uniqExact_diff,
    countIf(r.uq != d.uq)                     AS uniq_diff,
    countIf(r.comb != d.comb)                 AS uniqCombined_diff,
    countIf(r.comb12 != d.comb12)             AS uniqCombined12_diff,
    countIf(r.hll12 != d.hll12)               AS uniqHLL12_diff,
    -- where uniqCombined(12) differs: the true distinct counts of those groups and the largest gap
    minIf(d.exact, r.comb12 != d.comb12)      AS comb12_diff_min_true,
    maxIf(d.exact, r.comb12 != d.comb12)      AS comb12_diff_max_true,
    maxIf(abs(toInt64(r.comb12) - toInt64(d.comb12)), r.comb12 != d.comb12) AS comb12_max_gap
FROM
(
    SELECT bucket, kind, page, 1 AS bucket_ok,
           sum(events)                          AS events,
           uniqExactMerge(u_exact_u64)          AS exact,
           uniqMerge(u_uniq_u64)                AS uq,
           uniqCombinedMerge(u_comb_u64)        AS comb,
           uniqCombinedMerge(12)(u_comb12_u64)  AS comb12,
           uniqHLL12Merge(u_hll12_u64)          AS hll12
    FROM mv_uniq.rollup_10m
    GROUP BY bucket, kind, page
) AS r
FULL OUTER JOIN
(
    SELECT toStartOfTenMinutes(ts) AS bucket, kind, page, 1 AS bucket_ok,
           count()                    AS events,
           uniqExact(user_u64)        AS exact,
           uniq(user_u64)             AS uq,
           uniqCombined(user_u64)     AS comb,
           uniqCombined(12)(user_u64) AS comb12,
           uniqHLL12(user_u64)        AS hll12
    FROM mv_uniq.events
    GROUP BY bucket, kind, page
) AS d USING (bucket, kind, page);

-- Negative control: adding up per-minute distinct counts is the mistake a cascade must not make.
-- The same comparison has to find mismatches here, or the check above proves nothing.
SELECT
    count()                          AS groups,
    countIf(s.summed != d.exact)     AS mismatched_groups,
    round(avg(s.summed / d.exact), 3) AS avg_summed_to_true
FROM
(
    SELECT toStartOfTenMinutes(bucket) AS b10, kind, page, sum(m) AS summed
    FROM
    (
        SELECT bucket, kind, page, uniqExactMerge(u_exact_u64) AS m
        FROM mv_uniq.rollup_1m
        GROUP BY bucket, kind, page
    )
    GROUP BY b10, kind, page
) AS s
INNER JOIN
(
    SELECT toStartOfTenMinutes(ts) AS b10, kind, page, uniqExact(user_u64) AS exact
    FROM mv_uniq.events
    GROUP BY b10, kind, page
) AS d USING (b10, kind, page);

-- Repeatability: the same direct 10-minute computation three times, then twice with max_threads = 1.
-- Each cell is a fingerprint of all 144,000 group results; a column whose value changes between
-- runs gave different answers for the same data.
SELECT 'run 1' AS run, max_threads_default AS threads,
       groupBitXor(cityHash64(b, k, p, uq)) AS uniq_fp, groupBitXor(cityHash64(b, k, p, comb)) AS uniqCombined_fp,
       groupBitXor(cityHash64(b, k, p, comb12)) AS uniqCombined12_fp, groupBitXor(cityHash64(b, k, p, hll12)) AS uniqHLL12_fp
FROM (SELECT 'default' AS max_threads_default, toStartOfTenMinutes(ts) AS b, kind AS k, page AS p, uniq(user_u64) AS uq,
             uniqCombined(user_u64) AS comb, uniqCombined(12)(user_u64) AS comb12, uniqHLL12(user_u64) AS hll12
      FROM mv_uniq.events GROUP BY b, k, p)
GROUP BY threads;
SELECT 'run 2' AS run, max_threads_default AS threads,
       groupBitXor(cityHash64(b, k, p, uq)) AS uniq_fp, groupBitXor(cityHash64(b, k, p, comb)) AS uniqCombined_fp,
       groupBitXor(cityHash64(b, k, p, comb12)) AS uniqCombined12_fp, groupBitXor(cityHash64(b, k, p, hll12)) AS uniqHLL12_fp
FROM (SELECT 'default' AS max_threads_default, toStartOfTenMinutes(ts) AS b, kind AS k, page AS p, uniq(user_u64) AS uq,
             uniqCombined(user_u64) AS comb, uniqCombined(12)(user_u64) AS comb12, uniqHLL12(user_u64) AS hll12
      FROM mv_uniq.events GROUP BY b, k, p)
GROUP BY threads;
SELECT 'run 3' AS run, max_threads_default AS threads,
       groupBitXor(cityHash64(b, k, p, uq)) AS uniq_fp, groupBitXor(cityHash64(b, k, p, comb)) AS uniqCombined_fp,
       groupBitXor(cityHash64(b, k, p, comb12)) AS uniqCombined12_fp, groupBitXor(cityHash64(b, k, p, hll12)) AS uniqHLL12_fp
FROM (SELECT 'default' AS max_threads_default, toStartOfTenMinutes(ts) AS b, kind AS k, page AS p, uniq(user_u64) AS uq,
             uniqCombined(user_u64) AS comb, uniqCombined(12)(user_u64) AS comb12, uniqHLL12(user_u64) AS hll12
      FROM mv_uniq.events GROUP BY b, k, p)
GROUP BY threads;
SELECT 'run 4' AS run, max_threads_default AS threads,
       groupBitXor(cityHash64(b, k, p, uq)) AS uniq_fp, groupBitXor(cityHash64(b, k, p, comb)) AS uniqCombined_fp,
       groupBitXor(cityHash64(b, k, p, comb12)) AS uniqCombined12_fp, groupBitXor(cityHash64(b, k, p, hll12)) AS uniqHLL12_fp
FROM (SELECT '1' AS max_threads_default, toStartOfTenMinutes(ts) AS b, kind AS k, page AS p, uniq(user_u64) AS uq,
             uniqCombined(user_u64) AS comb, uniqCombined(12)(user_u64) AS comb12, uniqHLL12(user_u64) AS hll12
      FROM mv_uniq.events GROUP BY b, k, p)
GROUP BY threads
SETTINGS max_threads = 1;
SELECT 'run 5' AS run, max_threads_default AS threads,
       groupBitXor(cityHash64(b, k, p, uq)) AS uniq_fp, groupBitXor(cityHash64(b, k, p, comb)) AS uniqCombined_fp,
       groupBitXor(cityHash64(b, k, p, comb12)) AS uniqCombined12_fp, groupBitXor(cityHash64(b, k, p, hll12)) AS uniqHLL12_fp
FROM (SELECT '1' AS max_threads_default, toStartOfTenMinutes(ts) AS b, kind AS k, page AS p, uniq(user_u64) AS uq,
             uniqCombined(user_u64) AS comb, uniqCombined(12)(user_u64) AS comb12, uniqHLL12(user_u64) AS hll12
      FROM mv_uniq.events GROUP BY b, k, p)
GROUP BY threads
SETTINGS max_threads = 1;
