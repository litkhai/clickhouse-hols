-- 04-rollup-size.sql: what the rollups hold and how many bytes each column takes on disk.

-- Data size: raw rows and the two rollups (one active part each after 02-load.sql).
SELECT table, sum(rows) AS rows,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
       formatReadableSize(sum(data_compressed_bytes))   AS compressed,
       any(part_type) AS part_type
FROM system.parts
WHERE database = 'mv_uniq' AND active
GROUP BY table
ORDER BY table;

-- Distinct users per rollup row (group): this decides the state size.
SELECT table, count() AS groups,
       quantilesExact(0.5, 0.9, 0.99)(u) AS p50_p90_p99, max(u) AS max_users, sum(u) AS sum_users
FROM
(
    SELECT 'rollup_1m' AS table, uniqExactMerge(u_exact_u64) AS u FROM mv_uniq.rollup_1m GROUP BY bucket, kind, page
    UNION ALL
    SELECT 'rollup_10m', uniqExactMerge(u_exact_u64) FROM mv_uniq.rollup_10m GROUP BY bucket, kind, page
)
GROUP BY table
ORDER BY table;

-- Declared codec of every column (all pinned in 01-setup.sql).
SELECT table, groupUniqArray(compression_codec) AS codecs
FROM system.columns
WHERE database = 'mv_uniq' AND table IN ('rollup_1m', 'rollup_10m')
GROUP BY table
ORDER BY table;

-- State column types as the server stores them. On this build `uniq` carries a state version
-- (`AggregateFunction(1, uniq, …)`) although 01-setup.sql declares `AggregateFunction(uniq, …)`.
SELECT name, type
FROM system.columns
WHERE database = 'mv_uniq' AND table = 'rollup_1m' AND name LIKE 'u\\_%'
ORDER BY position;

-- Bytes per column. "rest" = the five columns every rollup has (bucket, kind, page, events, latency_sum).
-- share_pct = this state column / (rest + this state column): its share of a rollup that holds only it.
WITH cols AS
(
    SELECT table, column, sum(rows) AS rows,
           sum(column_data_uncompressed_bytes) AS unc,
           sum(column_data_compressed_bytes)   AS comp
    FROM system.parts_columns
    WHERE database = 'mv_uniq' AND table IN ('rollup_1m', 'rollup_10m') AND active
    GROUP BY table, column
),
rest AS
(
    SELECT table, sum(comp) AS rest_comp
    FROM cols
    WHERE column IN ('bucket', 'kind', 'page', 'events', 'latency_sum')
    GROUP BY table
)
SELECT c.table, c.column,
       formatReadableSize(c.unc)  AS uncompressed,
       formatReadableSize(c.comp) AS compressed,
       round(c.unc / c.rows, 1)   AS bytes_per_row,
       round(c.unc / c.comp, 2)   AS ratio,
       if(c.column LIKE 'u\\_%', round(100 * c.comp / (r.rest_comp + c.comp), 1), NULL) AS share_pct
FROM cols AS c
INNER JOIN rest AS r USING (table)
ORDER BY c.table, c.comp DESC;

-- The 1-minute total for "rest" alone: the size of a 1-minute rollup that holds no distinct count.
SELECT table, formatReadableSize(sum(column_data_compressed_bytes)) AS rest_compressed
FROM system.parts_columns
WHERE database = 'mv_uniq' AND table IN ('rollup_1m', 'rollup_10m') AND active
  AND column IN ('bucket', 'kind', 'page', 'events', 'latency_sum')
GROUP BY table
ORDER BY table;

-- 10-minute rollup against the 1-minute rollup, per column: rows fall by ~10x, state bytes do not.
SELECT column,
       round(sumIf(column_data_compressed_bytes, table = 'rollup_10m')
             / sumIf(column_data_compressed_bytes, table = 'rollup_1m'), 3) AS ratio_10m_to_1m
FROM system.parts_columns
WHERE database = 'mv_uniq' AND table IN ('rollup_1m', 'rollup_10m') AND active
GROUP BY column
ORDER BY ratio_10m_to_1m DESC;

SELECT round(sumIf(rows, table = 'rollup_10m') / sumIf(rows, table = 'rollup_1m'), 3) AS rows_10m_to_1m
FROM system.parts
WHERE database = 'mv_uniq' AND active;
