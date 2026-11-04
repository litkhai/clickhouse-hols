-- 01 — What the system database holds on a Cloud service (read-only)

SELECT version() AS version, uptime() AS uptime_s, getSetting('max_threads') AS max_threads;

-- Three kinds of table: in-memory views of the server's state (System* engines),
-- log tables (MergeTree, written by the server), and older generations of the
-- log tables (the _N suffix, see 03-log-history.sql).
SELECT
    multiIf(engine = 'MergeTree' AND match(name, '_[0-9]+$'), 'log table, older generation (_N)',
            engine = 'MergeTree', 'log table, current',
            engine = 'SharedMergeTree', 'SharedMergeTree',
            engine IN ('View', 'Dictionary'), engine,
            'in-memory (System* engine)') AS kind,
    count() AS tables
FROM system.tables
WHERE database = 'system'
GROUP BY kind
ORDER BY tables DESC;

-- The current log tables on the replica that answered: size and retention (TTL)
SELECT
    name,
    total_rows,
    formatReadableSize(total_bytes) AS size,
    extract(engine_full, 'TTL (.+?) SETTINGS') AS ttl
FROM system.tables
WHERE database = 'system' AND engine = 'MergeTree' AND match(name, '_log$')
ORDER BY total_bytes DESC;

-- Where a log table is stored: a storage policy on object storage, under a
-- prefix named after the replica that writes it
SELECT name, storage_policy, data_paths, partition_key, sorting_key
FROM system.tables
WHERE database = 'system' AND name = 'query_log'
FORMAT Vertical;

SELECT
    if(name LIKE '\_\_tmp\_internal\_%', '__tmp_internal_* (an older replica)', name) AS disk,
    any(type) AS type,
    any(metadata_type) AS metadata,
    any(is_read_only) AS read_only,
    count() AS disks
FROM system.disks
WHERE name LIKE 'diskPlainRewritableForSystemTables%' OR name LIKE '\_\_tmp\_internal\_%' OR name = 'default'
GROUP BY disk
ORDER BY disk;

-- Tables that exist only in Cloud (oss-diff.sh compares the full list with OSS)
SELECT name, engine
FROM system.tables
WHERE database = 'system'
  AND (name LIKE 'shared\_merge\_tree%' OR name LIKE 'distributed\_cache%' OR name LIKE 'merge\_coordinator%'
       OR name LIKE 'snapshot\_%' OR name LIKE 'stateless\_worker%' OR name LIKE 'system\_tables\_tracking\_%'
       OR name IN ('virtual_parts', 'merge_worker_state', 'custom_metrics', 'prometheus_metrics', 'clickpipes_log'))
ORDER BY name;

-- Logging settings. `changed` = 1: the service's settings profile sets it (the value can still
-- equal the built-in default; oss-diff.sh shows the OSS values)
SELECT name, value, changed
FROM system.settings
WHERE name IN ('log_queries', 'log_queries_probability', 'log_query_threads', 'log_query_views',
               'log_processors_profiles', 'log_profile_events', 'log_query_settings',
               'query_profiler_real_time_period_ns', 'query_profiler_cpu_time_period_ns',
               'opentelemetry_start_trace_probability', 'enable_blob_storage_log', 'enable_filesystem_cache_log')
ORDER BY changed DESC, name;
