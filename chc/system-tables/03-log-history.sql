-- 03 — Log history outlives the replica that wrote it (read-only)

-- Each replica holds the current query_log plus older generations query_log_N
SELECT
    hostName() AS replica,
    countIf(name = 'query_log') AS current,
    countIf(name != 'query_log') AS older_generations,
    count() AS query_log_tables
FROM clusterAllReplicas('default', system.tables)
WHERE database = 'system' AND match(name, '^query_log(_[0-9]+)?$')
GROUP BY replica
ORDER BY replica;

-- An older generation sits on a read-only disk whose path is another replica's prefix
SELECT p.table, p.disk_name, d.is_read_only AS read_only, d.path
FROM
(
    SELECT table, any(disk_name) AS disk_name
    FROM system.parts
    WHERE database = 'system' AND match(table, '^query_log(_[0-9]+)?$') AND active
    GROUP BY table
) AS p
INNER JOIN system.disks AS d ON d.name = p.disk_name
ORDER BY length(p.table), p.table
LIMIT 4;

-- The registry behind it: one SharedMergeTree table, the same rows on every replica.
-- origin_replica wrote the table; attached_replica_id is the live replica that mounted it.
SELECT
    ifNull(attached_replica_id, '(not attached)') AS attached_to,
    count() AS tables,
    uniqExact(origin_replica) AS origin_replicas,
    min(discovered_at) AS first_discovered,
    max(discovered_at) AS last_discovered
FROM merge('system', '^system_tables_tracking_')
GROUP BY attached_to
ORDER BY first_discovered DESC;

-- Older generations are not one per release: count the distinct schemas among the
-- query_log tables in the registry, mounted or not
SELECT
    attached_replica_id IS NOT NULL AS mounted,
    count() AS query_log_tables,
    uniqExact(cityHash64(schema)) AS distinct_schemas
FROM merge('system', '^system_tables_tracking_')
WHERE match(name, '^query_log(_[0-9]+)?$')
GROUP BY mounted
ORDER BY mounted DESC;

-- Every origin replica's query_log appears once, on exactly one live replica
SELECT
    hostName() AS live_replica,
    hostname AS origin_replica,
    count() AS rows,
    min(event_time) AS first_event,
    max(event_time) AS last_event,
    uniqExact(_table) AS tables
FROM clusterAllReplicas('default', merge('system', '^query_log'))
WHERE event_date >= today() - 3
GROUP BY live_replica, origin_replica
ORDER BY first_event;

-- How far back the history goes, against the 180-day TTL
SELECT
    min(event_date) AS oldest_visible,
    max(event_date) AS newest,
    dateDiff('day', min(event_date), today()) AS days_visible
FROM clusterAllReplicas('default', merge('system', '^query_log'));

-- The three ways to ask "how many queries this week", side by side
SELECT source, rows FROM
(
    SELECT 'system.query_log (one replica, current table)' AS source, count() AS rows
    FROM system.query_log WHERE event_date >= today() - 7
    UNION ALL
    SELECT 'clusterAllReplicas(default, system.query_log)', count()
    FROM clusterAllReplicas('default', system.query_log) WHERE event_date >= today() - 7
    UNION ALL
    SELECT 'clusterAllReplicas(default, merge(system, ^query_log))', count()
    FROM clusterAllReplicas('default', merge('system', '^query_log')) WHERE event_date >= today() - 7
)
ORDER BY rows;

-- What the history weighs: every generation of each log table, all replicas together
SELECT
    replaceRegexpOne(name, '_[0-9]+$', '') AS log_table,
    count() AS tables,
    sum(total_rows) AS rows,
    formatReadableSize(sum(total_bytes)) AS size
FROM clusterAllReplicas('default', system.tables)
WHERE database = 'system' AND engine = 'MergeTree'
GROUP BY log_table
ORDER BY sum(total_bytes) DESC
LIMIT 8;
