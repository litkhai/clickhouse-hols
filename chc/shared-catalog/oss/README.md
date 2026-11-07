# Shared catalog: OSS half

Issue: litkhai/clickhouse-hols#134 (questions 9-10). A local OSS cluster (1 Keeper, 2 servers `ch1` and `ch2`, cluster `c` = 1 shard x 2 replicas, macros `{shard}`=01, `{replica}`=ch1/ch2) that shows where the catalog lives: local metadata files, Keeper trees, or both.

Images: `clickhouse/clickhouse-server:26.8` and `clickhouse/clickhouse-keeper:26.8`.

## Run

```bash
./run.sh        # starts compose, runs steps 1-5, writes out/step*.txt and out/all.log
./run.sh down   # removes containers and volumes
```

Each step prints the statement, then the result. Statements that must fail are asserted (the run aborts if one succeeds) and the error code and message are printed. `out/` is git-ignored.

## Steps

1. Atomic database + `ReplicatedMergeTree`: what lives in Keeper and what stays local; ALTER, RENAME, DROP, and a plain view.
2. `ON CLUSTER`: the `/clickhouse/task_queue/ddl` entry, the timeout while a host is down, execution after the host returns.
3. `Replicated` database: `log/`, `metadata/`, `replicas/` trees; objects appear on the other replica without `ON CLUSTER`.
4. Replicated database limits (cross-database RENAME, UNDROP, CREATE AS SELECT into ReplicatedMergeTree and MergeTree, ON CLUSTER).
5. Recovery: (a) drop and recreate one replica, (b) a replica that fell behind with a diverged local table.

## What the 2026-11-07 run returned

Run date 2026-11-07 (UTC), `SELECT version()` on both servers: `26.8.36.3`, linux/arm64, Docker Desktop with 8 GB, full run 69 s. The log of that run is `runs/2026-11-07.txt`. Output below is trimmed from `out/`.

### 1. Atomic + ReplicatedMergeTree

- `CREATE TABLE analytics.events ... ReplicatedMergeTree('/clickhouse/tables/{shard}/events','{replica}')` on ch1 only: `SHOW TABLES FROM analytics` on ch2 returned nothing.
- Keeper `/clickhouse/tables/01/events` children (depth 3): `alter_partition_version, async_blocks, block_numbers, blocks, columns, deduplication_hashes, leader_election, lightweight_updates, log, lost_part_count, metadata, mutations, nonincrement_block_numbers, part_moves_shard, pinned_part_uuids, quorum, replicas, table_shared_id, temp`. `replicas/ch1` had 14 children: `columns, creator_info, flags, host, is_active, is_lost, log_pointer, max_processed_insert_time, metadata, metadata_version, min_unprocessed_insert_time, mutation_pointer, parts, queue`.
- `columns` node value: `columns format version: 1`, `2 columns:`, `` `id` UInt64 ``, `` `ts` DateTime ``. `metadata` node value: `metadata format version: 1`, `index granularity: 8192`, `primary key: id`, `data format version: 1`, `granularity bytes: 10485760`, `merge parameters format version: 2` (full text in `out/step1.txt`).
- Local on ch1: `/var/lib/clickhouse/metadata/analytics/events.sql` holds `ATTACH TABLE _ UUID '...' (id, ts) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}') ORDER BY id SETTINGS index_granularity = 8192`. `metadata/analytics` is a symlink to `../store/<3 chars>/<database uuid>`; `analytics.sql` is a 78-byte file next to it; data is under `store/<3 chars>/<table uuid>/`; the database store directory contains `events.sql`.
- After creating the same table on ch2: `replicas/` had `ch1` and `ch2` (14 children each).
- `ALTER TABLE analytics.events ADD COLUMN note String` on ch1 only (no ON CLUSTER): ch2's `SHOW CREATE TABLE` and its local `events.sql` now contained `` `note` String ``. The Keeper entry `/clickhouse/tables/01/events/log/log-0000000000` read `format version: 4`, `source replica: ch1`, type line `alter`, `alter_version 1`, then the new `columns` (3 columns) and `metadata` text.
- `RENAME TABLE analytics.events TO analytics.events_renamed` on ch1: `system.replicas` on ch1 still reported `zookeeper_path = /clickhouse/tables/01/events`; ch2 `SHOW TABLES` still listed `events`; Keeper `/clickhouse/tables/01` still had only `events`.
- `DROP TABLE analytics.events_renamed SYNC` on ch1: `replicas/` then had only `ch2`; ch2 still listed `events`.
- `CREATE VIEW analytics.plain_view_probe` on ch1: a walk of `/clickhouse` to depth 5 found 0 lines mentioning the name (top level: `sessions, tables, task_queue`); the view exists as `metadata/analytics/plain_view_probe.sql` (`ATTACH VIEW _ UUID ... AS SELECT 1 AS x`) on ch1 only; ch2 `SHOW TABLES` did not list it.

### 2. ON CLUSTER

- `CREATE TABLE analytics.t_cluster ON CLUSTER c ...` printed one row per host (`ch2 9000 0`, `ch1 9000 0`). Keeper node `/clickhouse/task_queue/ddl/query-0000000000` has children `active` and `finished`; `finished` has `ch1:9000` and `ch2:9000`, each with value `0`.
- Node value: `version: 5`, `query: CREATE TABLE analytics.t_cluster UUID '...' ON CLUSTER c (`id` UInt64) ENGINE = MergeTree ORDER BY id`, `hosts: ['ch1:9000','ch2:9000']`, `initiator: ch1:9000`, `tracing: ...`, `initial_query_id: ...`.
- Settings in `system.server_settings`: `distributed_ddl.path=/clickhouse/task_queue/ddl`, `replicas_path=/clickhouse/task_queue/replicas`, `pool_size=1`, `max_tasks_in_queue=1000`, `task_max_lifetime=604800`, `cleanup_delay_period=60`.
- With ch2 stopped and `distributed_ddl_task_timeout=10`: `Code: 159 ... Distributed DDL task /clickhouse/task_queue/ddl/query-0000000001 is not finished on 1 of 2 hosts (0 of them are currently executing the task, 0 are inactive). They are going to execute the query in background. Was waiting for 10.862 seconds, which is longer than distributed_ddl_task_timeout. (TIMEOUT_EXCEEDED)`. The table `t_late` already existed on ch1; the entry's `finished/` had only `ch1:9000`; the node value had an extra line `settings: distributed_ddl_task_timeout = 10`.
- After `docker compose start ch2`: ch2 listed `t_late` and `finished/` of that entry had both hosts.

### 3. Replicated database

- `CREATE DATABASE rdb ENGINE = Replicated('/clickhouse/databases/rdb','{shard}','{replica}')` on both; `CREATE TABLE rdb.t (...) ENGINE = ReplicatedMergeTree ORDER BY id` and `CREATE VIEW rdb.v` on ch1 only. ch2 listed `t` and `v`. The table's stored definition on ch2 expanded the engine arguments to `ReplicatedMergeTree('/clickhouse/tables/{uuid}/{shard}', '{replica}')`.
- Keeper `/clickhouse/databases/rdb`: `counter`, `first_replica_database_name` (= `rdb`), `log/`, `logs_to_keep` (= `1000`), `max_log_ptr` (= `4`), `metadata/`, `replicas/`.
- `log/`: `query-0000000001` and `-0000000002` (empty `query:`, one per replica creation, `committed` = `01|ch1` / `01|ch2`), `-0000000003` (`CREATE TABLE t UUID '...' (...)`), `-0000000004` (`CREATE VIEW v UUID '...'`); each has children `active, committed, finished, synced`.
- `metadata/`: nodes `t` and `v`, values are the full `ATTACH TABLE _ UUID '...' (...) ENGINE = ...` / `ATTACH VIEW _ UUID '...' ... AS SELECT id FROM rdb.t` text.
- `replicas/`: `01|ch1` and `01|ch2` (value `<host>:9000:<database uuid>`), each with `active, digest, log_ptr, max_log_ptr_at_creation, replica_group`; both had `log_ptr = 4` and the same `digest`.
- Local on ch1: `metadata/rdb.sql` = `ATTACH DATABASE _ UUID '...' ENGINE = Replicated('/clickhouse/databases/rdb', '{shard}', '{replica}')`; `metadata/rdb/` has `t.sql` and `v.sql`.

### 4. Replicated database limits

- `RENAME TABLE rdb.t TO analytics.t`: `Code: 48 ... Moving tables between databases is not supported for Replicated engine. (NOT_IMPLEMENTED)`
- `UNDROP TABLE rdb.tmp` (after dropping it): `Code: 344 ... Replicated database does not support UNDROP query. (SUPPORT_IS_DISABLED)`
- `CREATE TABLE … AS SELECT` with `database_replicated_allow_heavy_create = 0` (the default, `changed = 0`) depends on the target engine. With `ENGINE = ReplicatedMergeTree` it fails: `Code: 344 ... CREATE AS SELECT is not supported with Replicated databases. Consider using separate CREATE and INSERT queries. (SUPPORT_IS_DISABLED)`. With a plain `ENGINE = MergeTree` it succeeds, also with the setting passed explicitly as 0, and every replica runs the SELECT itself: `rdb.ctas` has 3 rows on ch1 and 3 rows on ch2, while the stored definition on ch2 has no SELECT (`CREATE TABLE rdb.ctas (`id` UInt64) ENGINE = MergeTree …`).
- `CREATE TABLE rdb.oc ON CLUSTER c ...` from ch1: failed, `Code: 80 ... There was an error on [ch2:9000]: Code: 80. ... It's not initial query. ON CLUSTER is not allowed for Replicated database. (INCORRECT_QUERY)`. `rdb.oc` existed on neither replica afterwards.
- `SYSTEM SYNC DATABASE REPLICA rdb` succeeded on ch1 and ch2.

### 5a. Drop and recreate one replica

- Before: `rdb/replicas` had `01|ch1`, `01|ch2`. `DROP DATABASE rdb SYNC` on ch2 only: `replicas/` had only `01|ch1`; ch1 still listed `ctas, ctas2, t, v`.
- `CREATE DATABASE rdb ENGINE = Replicated(...)` on ch2 again: ch2 listed `ctas, ctas2, t, v`; `replicas/` had both again, ch2 with a new database uuid.
- ch2 `system.text_log` (logger `DatabaseReplicated (rdb)`) for the second creation: `Will create new replica from log pointer 9`, `Got consistent metadata snapshot for log pointer 9`, `Executing CREATE TABLE rdb.t UUID ...` (and `ctas2`, `ctas`, `CREATE VIEW rdb.v`), `All tables are created successfully`. The strings `recoverLostReplica` and `Will recover replica` did not appear in this case; the replica was created, not recovered.

### 5b. Lost replica with a diverged local table

- `CREATE DATABASE rdb2 ... SETTINGS logs_to_keep=5` on ch1: Keeper `rdb2/logs_to_keep` = `5` (the setting is accepted in the engine's `SETTINGS` clause; `system.database_replicated_settings` does not exist in this version).
- `rdb2.local (a UInt32)` MergeTree created via the database (exists on both); 5 rows inserted on ch2 only (ch1: 0 rows).
- ch2 stopped. On ch1: `DROP TABLE rdb2.local SYNC`, `CREATE TABLE rdb2.local (b String, c Float64)`, then 12 x (CREATE + DROP of a filler table). ch1 state before ch2 started: `max_log_ptr = 29`, ch2 `log_ptr = 3`, `log/` still held 29 entries (`query-0000000001` to `-0000000029`, so no trimming had happened).
- ch2 started. ch2 text_log: `Will recover replica with staled log pointer 3 from log pointer 29`, `Table to detach local`, `Will recreate 1 broken tables to recover replica`, `Will RENAME TABLE local TO rdb2_broken_tables.local_29_<n>`, `Renaming table to path data/rdb2_broken_tables/local_29_<n>/`, `Executing CREATE TABLE rdb2.local UUID ... (`b` String, `c` Float64)`, `All tables are created successfully`, then `Marked recovered query-...` lines. Afterwards the replica's `log_ptr` = 29 on both, same `digest`.
- Result on ch2: new databases `rdb2_broken_tables` (Ordinary, created by the recovery) and `rdb2_broken_replicated_tables` (Atomic, empty). `rdb2_broken_tables.local_29_<n>` kept the old `(a UInt32)` definition and its 5 rows; `rdb2.local` on ch2 has the new columns and 0 rows. Nothing was dropped.
