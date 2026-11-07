#!/usr/bin/env bash
# 01 — What the service's catalog looks like before the lab touches it
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

echo "## version and replicas"
show "SELECT hostName() AS replica, version() AS version, uptime() AS uptime_s FROM clusterAllReplicas('default', system.one) ORDER BY replica"
show "SELECT cluster, count() AS replicas, groupArray(host_name) AS hosts, max(is_shared_catalog_cluster) AS shared_catalog FROM system.clusters GROUP BY cluster ORDER BY cluster"

echo "## database engines (system stays Atomic)"
show "SELECT engine, count() AS databases, if(engine = 'Shared', '(user databases, names not shown)', arrayStringConcat(groupArray(name), ', ')) AS names FROM system.databases GROUP BY engine ORDER BY databases DESC"

echo "## catalog objects and threads, per replica"
show "SELECT hostName() AS replica, name, value FROM clusterAllReplicas('default', system.metrics) WHERE name LIKE 'SharedCatalog%' OR name LIKE 'SharedDatabaseCatalog%' ORDER BY name, replica"
show "SELECT hostName() AS replica, name, value FROM clusterAllReplicas('default', system.events) WHERE name LIKE 'SharedDatabaseCatalog%' OR name LIKE 'SharedCatalog%' ORDER BY name, replica"

echo "## DDL settings as the service sets them"
show "SELECT name, value, default, changed FROM system.settings WHERE name IN ('distributed_ddl_output_mode','distributed_ddl_task_timeout','distributed_ddl_entry_format_version','database_shared_drop_table_delay_seconds','alter_sync','database_replicated_allow_heavy_create','ignore_on_cluster_for_replicated_database') ORDER BY name"
show "SELECT name, value FROM system.server_settings WHERE name ILIKE '%shared_catalog%' OR name ILIKE '%database_atomic_delay%' OR name ILIKE '%shared_database%' ORDER BY name"

echo "## Keeper: the connection is visible, the tree is not"
try zk_connection "SELECT name, host, port, index, connected_time, keeper_api_version, availability_zone FROM system.zookeeper_connection"
try zk_root "SELECT name FROM system.zookeeper WHERE path = '/'"
try zk_catalog "SELECT name FROM system.zookeeper WHERE path = '/clickhouse/catalog'"

echo "## the catalog's own log: one replica's last 30 minutes, by message shape"
show "SELECT level, count() AS n, any(substring(message, 1, 140)) AS example FROM system.text_log WHERE event_time > now() - INTERVAL 30 MINUTE AND logger_name = 'SharedDatabaseCatalog' GROUP BY level, replaceRegexpAll(message, '[0-9a-f-]{36}|[0-9.]+', 'N') ORDER BY n DESC LIMIT 25"
show "SELECT min(toUInt64OrZero(extract(message, 'version ([0-9]+)'))) AS first_version, max(toUInt64OrZero(extract(message, 'version ([0-9]+)'))) AS last_version, last_version - first_version AS versions_in_30min, countIf(message LIKE 'applyState: Successfully applied%') AS applies, round(quantile(0.5)(toFloat64OrZero(extract(message, 'in ([0-9.]+) seconds'))) * 1000, 1) AS p50_apply_ms FROM system.text_log WHERE event_time > now() - INTERVAL 30 MINUTE AND logger_name = 'SharedDatabaseCatalog' AND message LIKE 'applyState: Successfully applied state with version%'"
