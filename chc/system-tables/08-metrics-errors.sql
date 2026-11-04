-- 08 — Metrics, errors and logins (read-only)

-- How big is a replica? Read the cgroup, not the host: OS* metrics describe the machine underneath
SELECT hostName() AS replica, metric, value
FROM clusterAllReplicas('default', system.asynchronous_metrics)
WHERE metric IN ('CGroupMaxCPU', 'CGroupMemoryTotal', 'OSMemoryTotal', 'NumberOfCPUCores')
ORDER BY replica, metric;

-- Right now, per replica
SELECT hostName() AS replica, metric, value
FROM clusterAllReplicas('default', system.metrics)
WHERE metric IN ('Query', 'Merge', 'TCPConnection', 'HTTPConnection', 'BackgroundMergesAndMutationsPoolTask')
ORDER BY replica, metric;

-- The last 5 minutes, one row per minute and replica (metric_log samples every second)
SELECT
    toStartOfMinute(event_time) AS minute,
    hostName() AS replica,
    formatReadableSize(max(CurrentMetric_MemoryTracking)) AS peak_memory,
    sum(ProfileEvent_Query) AS queries,
    sum(ProfileEvent_InsertedRows) AS inserted_rows,
    sum(ProfileEvent_MergedRows) AS merged_rows
FROM clusterAllReplicas('default', system.metric_log)
WHERE event_date = today() AND event_time > now() - INTERVAL 5 MINUTE
GROUP BY minute, replica
HAVING inserted_rows > 0 OR merged_rows > 0
ORDER BY minute, replica;

-- Error counters since each replica started (a re-run adds to them); the lab's error
-- counts only on the replica that ran the failing query
SELECT hostName() AS replica, name, code, value, last_error_time
FROM clusterAllReplicas('default', system.errors)
WHERE name = 'CANNOT_PARSE_DATE'
ORDER BY replica;

-- The same error with history, from error_log
SELECT hostName() AS replica, error, count() AS samples, max(value) AS counter, max(event_time) AS last
FROM clusterAllReplicas('default', system.error_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run) AND error = 'CANNOT_PARSE_DATE'
GROUP BY replica, error
ORDER BY replica;

-- Logins by this user in the last hour: interface and authentication method
SELECT type, interface, auth_type, count() AS events
FROM clusterAllReplicas('default', system.session_log)
WHERE event_date = today() AND event_time > now() - INTERVAL 1 HOUR AND user = currentUser()
GROUP BY type, interface, auth_type
ORDER BY events DESC;

-- The built-in dashboards are rows in a table, with the SQL each chart runs
SELECT dashboard, count() AS charts
FROM system.dashboards
GROUP BY dashboard
ORDER BY dashboard;

SELECT title, query
FROM system.dashboards
WHERE dashboard = 'Cloud overview' AND title = 'FS cache hit rate'
FORMAT Vertical;
