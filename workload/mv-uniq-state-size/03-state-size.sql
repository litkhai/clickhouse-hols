-- 03-state-size.sql: how big one state is, by state function, distinct values per group and input type.
-- length(CAST(state AS String)) is the serialized state, the bytes a rollup row stores for it.
-- Independent of the rollup tables; values come from numbers().

-- (a) Bytes per state by distinct values per group (input UInt64, sipHash64 of distinct integers).
SELECT
    n                                                        AS distinct_values,
    length(CAST(uniqState(v) AS String))                     AS uniq,
    length(CAST(uniqCombinedState(v) AS String))             AS uniqCombined,
    length(CAST(uniqCombinedState(12)(v) AS String))         AS uniqCombined_12,
    length(CAST(uniqHLL12State(v) AS String))                AS uniqHLL12,
    length(CAST(uniqExactState(v) AS String))                AS uniqExact
FROM
(
    SELECT n, sipHash64(number) AS v
    FROM numbers(1000000)
    ARRAY JOIN arrayFilter(x -> number < x, [1, 10, 30, 100, 300, 600, 700, 1000, 3000, 10000, 30000, 100000, 1000000]) AS n
)
GROUP BY n
ORDER BY n;

-- (b) The same distinct values as String (32 hex characters), Nullable(String), UInt64 and UInt32.
-- Bytes per state; one row per state function and distinct count.
SELECT fn, n AS distinct_values, s_str AS String, s_nstr AS Nullable_String, s_u64 AS UInt64, s_u32 AS UInt32
FROM
(
    SELECT
        n,
        ['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12', 'uniqExact'] AS fns,
        [length(CAST(uniqState(str) AS String)), length(CAST(uniqCombinedState(str) AS String)),
         length(CAST(uniqCombinedState(12)(str) AS String)), length(CAST(uniqHLL12State(str) AS String)),
         length(CAST(uniqExactState(str) AS String))] AS a_str,
        [length(CAST(uniqState(nstr) AS String)), length(CAST(uniqCombinedState(nstr) AS String)),
         length(CAST(uniqCombinedState(12)(nstr) AS String)), length(CAST(uniqHLL12State(nstr) AS String)),
         length(CAST(uniqExactState(nstr) AS String))] AS a_nstr,
        [length(CAST(uniqState(u64) AS String)), length(CAST(uniqCombinedState(u64) AS String)),
         length(CAST(uniqCombinedState(12)(u64) AS String)), length(CAST(uniqHLL12State(u64) AS String)),
         length(CAST(uniqExactState(u64) AS String))] AS a_u64,
        [length(CAST(uniqState(u32) AS String)), length(CAST(uniqCombinedState(u32) AS String)),
         length(CAST(uniqCombinedState(12)(u32) AS String)), length(CAST(uniqHLL12State(u32) AS String)),
         length(CAST(uniqExactState(u32) AS String))] AS a_u32
    FROM
    (
        SELECT n, hex(MD5(toString(number))) AS str, toNullable(hex(MD5(toString(number)))) AS nstr,
               sipHash64(number) AS u64, toUInt32(number) AS u32
        FROM numbers(10000)
        ARRAY JOIN arrayFilter(x -> number < x, [100, 1000, 10000]) AS n
    )
    GROUP BY n
)
ARRAY JOIN fns AS fn, a_str AS s_str, a_nstr AS s_nstr, a_u64 AS s_u64, a_u32 AS s_u32
ORDER BY indexOf(['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12', 'uniqExact'], fn), n;

-- (c) Relative error against the true count: 10 groups per distinct count, disjoint values.
-- uniqExact is the control: its error must be 0.
SELECT fn, n AS distinct_values,
       round(avg(abs(est - n) / n) * 100, 3) AS mean_err_pct,
       round(max(abs(est - n) / n) * 100, 3) AS max_err_pct
FROM
(
    SELECT g, n,
           ['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12', 'uniqExact'] AS fns,
           [uniq(v), uniqCombined(v), uniqCombined(12)(v), uniqHLL12(v), uniqExact(v)] AS ests
    FROM
    (
        SELECT g, n, sipHash64(g, number) AS v
        FROM numbers(1000000)
        ARRAY JOIN arrayFilter(x -> number < x, [10, 100, 1000, 10000, 100000, 1000000]) AS n
        ARRAY JOIN range(10) AS g
    )
    GROUP BY g, n
)
ARRAY JOIN fns AS fn, ests AS est
GROUP BY fn, n
ORDER BY indexOf(['uniq', 'uniqCombined', 'uniqCombined(12)', 'uniqHLL12', 'uniqExact'], fn), n;
