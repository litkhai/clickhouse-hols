-- 07 — Parts are shared, part events are not (read-only)

-- system.parts reads SharedMergeTree metadata: every replica reports the same parts
SELECT hostName() AS replica, count() AS active_parts, sum(rows) AS rows, sum(marks) AS marks
FROM clusterAllReplicas('default', system.parts)
WHERE database = 'systables_lab' AND table = 'events' AND active
GROUP BY replica
ORDER BY replica;

-- system.part_log is a log table: each event is recorded on the replica that did the work
SELECT hostName() AS replica, table, event_type, merge_reason, count() AS events, sum(rows) AS rows
FROM clusterAllReplicas('default', system.part_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run) AND database = 'systables_lab'
GROUP BY replica, table, event_type, merge_reason
ORDER BY replica, table, event_type;

-- Which insert made which part (query_id joins part_log to query_log)
SELECT p.part_name, p.rows, q.log_comment, p.hostname AS replica
FROM clusterAllReplicas('default', system.part_log) AS p
INNER JOIN clusterAllReplicas('default', system.query_log) AS q ON p.query_id = q.query_id
WHERE p.event_date = today() AND q.event_date = today()
  AND p.event_time >= (SELECT max(started) FROM systables_lab.run)
  AND p.database = 'systables_lab' AND p.table = 'events' AND p.event_type = 'NewPart'
  AND q.type = 'QueryFinish' AND q.log_comment LIKE 'lab:insert-%'
ORDER BY q.log_comment;

-- The mutation
SELECT mutation_id, command, is_done, parts_to_do, latest_fail_reason
FROM system.mutations
WHERE database = 'systables_lab';

-- Merges running right now, on any replica (usually empty by the time you look)
SELECT hostName() AS replica, table, round(elapsed, 1) AS elapsed_s, round(progress, 2) AS progress
FROM clusterAllReplicas('default', system.merges)
WHERE database = 'systables_lab';

-- Parts replaced by merges, kept until no query or snapshot needs them (SharedMergeTree only)
SELECT table, count() AS outdated_parts
FROM system.shared_merge_tree_outdated_parts
WHERE database = 'systables_lab'
GROUP BY table;
