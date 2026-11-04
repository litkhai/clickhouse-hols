-- 02 — One service, several replicas (read-only)

-- Every replica of this service. 'default' is the cluster name in Cloud.
SELECT hostName() AS replica, version() AS version, uptime() AS uptime_s
FROM clusterAllReplicas('default', system.one)
ORDER BY replica;

-- The clusters a query can address. With compute-compute separation, a second
-- cluster spans every service (compute group) of the warehouse.
SELECT cluster, count() AS replicas
FROM system.clusters
GROUP BY cluster
ORDER BY cluster;

-- The same table asked of each replica: query_log rows today, per replica
SELECT hostName() AS replica, count() AS query_log_rows_today
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today()
GROUP BY replica
ORDER BY replica;
