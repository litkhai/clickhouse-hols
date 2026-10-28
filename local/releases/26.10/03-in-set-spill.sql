-- ClickHouse 26.10 — sets built for IN spill to disk
--
--   max_bytes_ratio_before_external_set = 0.5   (new, on by default)
--   max_bytes_before_external_set       = 0     (new, absolute threshold)
--
-- x IN (SELECT ...) builds a hash set of the subquery's result before the outer
-- query reads a row. Until 26.10 that set had to fit in memory, so a large
-- subquery under a memory limit failed with MEMORY_LIMIT_EXCEEDED in
-- CreatingSetsTransform. Now the set is written to disk in parts once it passes
-- a threshold, and merged back for the lookup.
--
-- The default is a ratio: half of the memory available under the SERVER or USER
-- limit, measured when the query starts. It does NOT look at a per-query
-- max_memory_usage. That is the line to remember, and section 3 is about it:
-- a query capped at 400 MB with nothing else set still fails, because half of
-- the server's memory is far above 400 MB. To spill under a per-query cap, set
-- max_bytes_before_external_set below the cap.
--
-- The failing runs are in 03-in-set-spill.sh.

SELECT '════════ 1. A 20-million-key set ════════' AS section;

DROP TABLE IF EXISTS ids;
CREATE TABLE ids (k UInt64) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO ids SELECT intHash64(number) FROM numbers(20000000);

-- Every probe value is in the set, so each count is 2,000,000.
SELECT name, value FROM system.settings
WHERE name IN ('max_bytes_ratio_before_external_set', 'max_bytes_before_external_set')
ORDER BY name;

SELECT '════════ 2. In memory, and spilled ════════' AS section;

-- Default settings, no per-query cap: the set stays in memory.
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) IN (SELECT k FROM ids)
SETTINGS log_comment = 'set_in_memory';

-- An absolute threshold of 100 MB: the set goes to disk in parts.
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) IN (SELECT k FROM ids)
SETTINGS max_bytes_before_external_set = 100000000, log_comment = 'set_spilled';

-- The same threshold under a 400 MB cap. The in-memory set needs about 770 MB,
-- so this query cannot run without spilling. It does.
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) IN (SELECT k FROM ids)
SETTINGS max_memory_usage = 400000000, max_bytes_before_external_set = 100000000,
         log_comment = 'set_spilled_capped';

-- NOT IN and GLOBAL IN build the same set and spill the same way.
SELECT count() FROM numbers(2000000)
WHERE intHash64(number) NOT IN (SELECT k FROM ids)
SETTINGS max_bytes_before_external_set = 100000000, log_comment = 'set_spilled_not_in';

SYSTEM FLUSH LOGS query_log;

SELECT '════════ 3. What query_log says ════════' AS section;

-- spilled_to_disk is new in 26.10 and names the operator that spilled: 'set'.
-- Peak memory falls from ~770 MiB to ~155 MiB, for 1.3 to 2 times the run time
-- across the runs behind the README.
SELECT log_comment, formatReadableSize(memory_usage) AS peak_memory, spilled_to_disk, query_duration_ms
FROM (
    SELECT * FROM system.query_log
    WHERE log_comment LIKE 'set_%' AND type = 'QueryFinish'
    ORDER BY event_time_microseconds DESC
    LIMIT 1 BY log_comment
)
ORDER BY log_comment;

SELECT '-- 3b. the profile events behind it' AS note;
SELECT
    ProfileEvents['ExternalSetWritePart']                         AS parts_written,
    ProfileEvents['ExternalSetMerge']                             AS merges,
    formatReadableSize(ProfileEvents['ExternalSetCompressedBytes']) AS on_disk,
    ProfileEvents['ExternalSetTailKeptKeys']                      AS keys_kept_in_memory
FROM system.query_log
WHERE log_comment = 'set_spilled' AND type = 'QueryFinish'
ORDER BY event_time_microseconds DESC
LIMIT 1;
