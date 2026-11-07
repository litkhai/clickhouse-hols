-- 01 — What a plain CREATE TABLE becomes on Cloud

CREATE DATABASE IF NOT EXISTS smt_lab;

-- Each run is stamped; later steps read only log rows written after it.
CREATE TABLE IF NOT EXISTS smt_lab.run (started DateTime64(6)) ENGINE = MergeTree ORDER BY started;

INSERT INTO smt_lab.run SELECT now64(6);

-- The database engine is Shared, and ENGINE = MergeTree is stored as SharedMergeTree
CREATE TABLE IF NOT EXISTS smt_lab.big (id UInt64, s String) ENGINE = MergeTree ORDER BY id;

SELECT name, engine FROM system.databases WHERE name = 'smt_lab';

SELECT name, engine, engine_full FROM system.tables WHERE database = 'smt_lab' AND name = 'big' FORMAT Vertical;

-- The 'default' cluster: one shard, one row per replica
SELECT cluster, shard_num, replica_num, host_name FROM system.clusters WHERE cluster = 'default' ORDER BY replica_num;

-- Every replica keeps its own replica entry for the table; the Keeper path is per table UUID
SELECT hostName() AS replica, is_leader, is_parts_update_leader, merge_coordinator_replica,
       total_replicas, active_replicas, queue_size, log_pointer, zookeeper_path
FROM clusterAllReplicas('default', system.replicas)
WHERE database = 'smt_lab' AND table = 'big'
ORDER BY replica;

-- MergeTree settings that shape parts on Cloud. changed = 1: the service differs from the
-- built-in default. min_bytes_for_wide_part decides Compact (one file for all columns) vs Wide.
SELECT name, value, default, changed
FROM system.merge_tree_settings
WHERE name IN ('storage_policy', 'min_bytes_for_wide_part', 'min_bytes_for_full_part_storage',
               'parts_to_delay_insert', 'parts_to_throw_insert', 'max_parts_in_total',
               'replicated_deduplication_window', 'replicated_deduplication_window_seconds')
ORDER BY name;

-- The insert settings that matter for consistency, as this service has them
SELECT name, value, changed
FROM system.settings
WHERE name IN ('insert_quorum', 'insert_quorum_parallel', 'select_sequential_consistency',
               'async_insert', 'wait_for_async_insert', 'async_insert_busy_timeout_max_ms', 'insert_keeper_max_retries')
ORDER BY name;
