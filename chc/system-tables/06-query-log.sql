-- 06 — Reading query_log in Cloud (read-only)

-- Log rows are buffered and flushed every few seconds. Flush every replica now.
SYSTEM FLUSH LOGS ON CLUSTER 'default';

-- The lab's own queries, wherever they ran
SELECT
    event_time,
    hostName() AS replica,
    log_comment,
    type,
    query_duration_ms AS ms,
    read_rows,
    formatReadableSize(read_bytes) AS read,
    written_rows,
    formatReadableSize(memory_usage) AS memory
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run)
  AND log_comment LIKE 'lab:%' AND type != 'QueryStart'
ORDER BY event_time_microseconds;

-- Where the bytes came from: the filesystem cache or object storage (S3)
SELECT
    log_comment,
    ProfileEvents['SelectedParts'] AS parts,
    ProfileEvents['SelectedMarks'] AS marks,
    formatReadableSize(ProfileEvents['CachedReadBufferReadFromCacheBytes']) AS from_cache,
    formatReadableSize(ProfileEvents['CachedReadBufferReadFromSourceBytes']) AS from_source,
    formatReadableSize(ProfileEvents['ReadBufferFromS3Bytes']) AS s3_bytes,
    ProfileEvents['S3GetObject'] AS s3_get,
    round(ProfileEvents['RealTimeMicroseconds'] / 1e6, 2) AS thread_s
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run)
  AND log_comment LIKE 'lab:q-%' AND type = 'QueryFinish'
ORDER BY event_time_microseconds;

-- Did the primary key help? Marks selected out of the marks in the table
SELECT
    log_comment,
    ProfileEvents['SelectedMarks'] AS selected_marks,
    (SELECT sum(marks) FROM system.parts WHERE database = 'systables_lab' AND table = 'events' AND active) AS total_marks,
    read_rows
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run)
  AND log_comment IN ('lab:q-pk', 'lab:q-no-pk') AND type = 'QueryFinish'
ORDER BY log_comment;

-- Failures: type and exception code
SELECT
    event_time,
    hostName() AS replica,
    type,
    exception_code,
    errorCodeToName(exception_code) AS error,
    substring(exception, 1, 70) AS message
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run)
  AND log_comment = 'lab:q-error' AND type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing');

-- The materialized view behind each insert
SELECT
    hostName() AS replica,
    view_name,
    view_type,
    status,
    read_rows,
    written_rows,
    view_duration_ms
FROM clusterAllReplicas('default', system.query_views_log)
WHERE event_date = today() AND event_time >= (SELECT max(started) FROM systables_lab.run)
  AND view_name = 'systables_lab.daily_mv'
ORDER BY event_time_microseconds;

-- Who fills query_log on a Cloud service: most rows are the platform's own users
SELECT
    multiIf(user LIKE '%-internal', 'platform (*-internal)',
            user = '', '(no user: background tasks)',
            user LIKE 'clickpipe:%', 'ClickPipes',
            'everyone else') AS who,
    count() AS queries,
    round(100 * count() / sum(count()) OVER (), 1) AS pct,
    formatReadableSize(sum(read_bytes)) AS read
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date >= today() - 1 AND type != 'QueryStart'
GROUP BY who
ORDER BY queries DESC;

-- Top query shapes in the last day, platform users left out
SELECT
    normalized_query_hash,
    any(user) AS any_user,
    count() AS runs,
    round(avg(query_duration_ms)) AS avg_ms,
    formatReadableSize(sum(read_bytes)) AS read_total,
    substring(any(normalizeQuery(query)), 1, 60) AS query_shape
FROM clusterAllReplicas('default', system.query_log)
WHERE event_date >= today() - 1 AND type = 'QueryFinish' AND user NOT LIKE '%-internal' AND user != ''
  AND log_comment LIKE 'lab:%' AND event_time >= (SELECT max(started) FROM systables_lab.run)
GROUP BY normalized_query_hash
ORDER BY sum(read_bytes) DESC
LIMIT 5;
