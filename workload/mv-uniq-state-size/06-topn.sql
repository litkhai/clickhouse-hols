-- 06-topn.sql: Top 10 and Bottom 10 pages by distinct users over the last hour (02:00 to 02:59),
-- the same query on every state column, on the 10-minute rollup and on the raw rows.
-- Bottom 10 counts only pages with at least 1,000 events in the hour.
-- run.sh runs this file five times; 08-timing.sql reads the runs from system.query_log by log_comment.

-- 1m uniq(String)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqMerge(u_uniq_str) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniq(String)'
FORMAT Null;

-- 1m uniq(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqMerge(u_uniq_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniq(UInt64)'
FORMAT Null;

-- 1m uniq(UInt32)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqMerge(u_uniq_u32) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniq(UInt32)'
FORMAT Null;

-- 1m uniqCombined(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqCombinedMerge(u_comb_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqCombined(UInt64)'
FORMAT Null;

-- 1m uniqCombined(12)(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqCombinedMerge(12)(u_comb12_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqCombined(12)(UInt64)'
FORMAT Null;

-- 1m uniqHLL12(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqHLL12Merge(u_hll12_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqHLL12(UInt64)'
FORMAT Null;

-- 1m uniqExact(String)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqExactMerge(u_exact_str) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqExact(String)'
FORMAT Null;

-- 1m uniqExact(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqExactMerge(u_exact_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqExact(UInt64)'
FORMAT Null;

-- 1m uniqExact(UInt32)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqExactMerge(u_exact_u32) AS users, sum(events) AS events
        FROM mv_uniq.rollup_1m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 1m uniqExact(UInt32)'
FORMAT Null;

-- 10m uniq(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqMerge(u_uniq_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_10m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 10m uniq(UInt64)'
FORMAT Null;

-- 10m uniqExact(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqExactMerge(u_exact_u64) AS users, sum(events) AS events
        FROM mv_uniq.rollup_10m
        WHERE bucket >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn 10m uniqExact(UInt64)'
FORMAT Null;

-- raw uniq(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniq(user_u64) AS users, count() AS events
        FROM mv_uniq.events
        WHERE ts >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn raw uniq(UInt64)'
FORMAT Null;

-- raw uniqExact(UInt64)
SELECT page, users, events, top_rank, bottom_rank
FROM
(
    SELECT page, users, events,
           row_number() OVER (ORDER BY users DESC, page)                    AS top_rank,
           row_number() OVER (ORDER BY events >= 1000 DESC, users ASC, page) AS bottom_rank
    FROM
    (
        SELECT page, uniqExact(user_u64) AS users, count() AS events
        FROM mv_uniq.events
        WHERE ts >= '2026-11-01 02:00:00'
        GROUP BY page
    )
)
WHERE top_rank <= 10 OR (bottom_rank <= 10 AND events >= 1000)
ORDER BY top_rank
SETTINGS log_comment = 'topn raw uniqExact(UInt64)'
FORMAT Null;
