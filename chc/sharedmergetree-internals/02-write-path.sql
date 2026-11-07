-- 02 — One INSERT: what is written, where, and what the other replica does

-- 2M rows of ~100-byte strings. max_insert_block_size splits it into parts of about 1M rows.
INSERT INTO smt_lab.big SETTINGS log_comment = 'lab:insert-big'
SELECT number, randomPrintableASCII(100) FROM numbers(2000000);

-- part_log is flushed every few seconds; wait, then flush every replica
SELECT sleep(3) AS waited;

SYSTEM FLUSH LOGS ON CLUSTER 'default';

-- NewPart on the replica that ran the INSERT; DownloadPart on the other one.
-- s3_read / s3_written: bytes each event moved to or from object storage.
SELECT hostName() AS replica, event_type, part_name, part_type, rows,
       formatReadableSize(size_in_bytes) AS part_size, duration_ms,
       formatReadableSize(ProfileEvents['WriteBufferFromS3Bytes']) AS s3_written,
       formatReadableSize(ProfileEvents['ReadBufferFromS3Bytes']) AS s3_read,
       ProfileEvents['S3GetObject'] AS s3_get
FROM clusterAllReplicas('default', system.part_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM smt_lab.run)
  AND database = 'smt_lab' AND table = 'big'
ORDER BY event_time_microseconds;

-- The same parts, from each replica's point of view
SELECT hostName() AS replica, count() AS active_parts, sum(rows) AS rows, formatReadableSize(sum(bytes_on_disk)) AS size
FROM clusterAllReplicas('default', system.parts)
WHERE database = 'smt_lab' AND table = 'big' AND active
GROUP BY replica
ORDER BY replica;

-- Nothing is queued for replication: the ReplicatedMergeTree queue tables are empty for this table
SELECT hostName() AS replica,
       (SELECT count() FROM system.replication_queue WHERE database = 'smt_lab') AS replication_queue,
       (SELECT count() FROM system.replicated_fetches WHERE database = 'smt_lab') AS replicated_fetches
FROM clusterAllReplicas('default', system.one)
ORDER BY replica;

-- The INSERT itself: duration, object storage writes, Keeper requests
SELECT hostName() AS replica, query_duration_ms, written_rows, formatReadableSize(written_bytes) AS written,
       formatReadableSize(ProfileEvents['WriteBufferFromS3Bytes']) AS s3_written,
       ProfileEvents['WriteBufferFromS3RequestsErrors'] AS s3_write_errors,
       ProfileEvents['ZooKeeperTransactions'] AS keeper_requests,
       ProfileEvents['ZooKeeperMulti'] AS keeper_multi,
       round(ProfileEvents['ZooKeeperWaitMicroseconds'] / 1000, 1) AS keeper_wait_ms
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM smt_lab.run)
  AND type = 'QueryFinish' AND log_comment = 'lab:insert-big'
FORMAT Vertical;

-- The Keeper requests the insert path made for this table, by Keeper node.
-- aggregated_zookeeper_log groups requests per component, operation and parent path.
SELECT hostName() AS replica, component, operation,
       replaceRegexpOne(parent_path, '^/clickhouse/tables/[^/]+/[^/]+', '<table>') AS path,
       sum(count) AS requests
FROM clusterAllReplicas('default', system.aggregated_zookeeper_log)
WHERE event_date = today() AND event_time >= toDateTime((SELECT max(started) FROM smt_lab.run))
  AND parent_path LIKE concat('/clickhouse/tables/', (SELECT toString(uuid) FROM system.tables WHERE database = 'smt_lab' AND name = 'big'), '%')
  AND component LIKE 'SharedMergeTreeSink%'
GROUP BY replica, component, operation, path
ORDER BY replica, path, operation;
