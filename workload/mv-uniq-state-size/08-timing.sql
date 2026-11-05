-- 08-timing.sql: the 06-topn.sql runs from system.query_log (run.sh runs 06 five times; tools/hol once).
-- read_from_disk = ProfileEvents ReadCompressedBytes (bytes read from compressed files, before decompression),
-- decompressed = CompressedReadBufferBytes (the same data after decompression). query_log read_bytes is the
-- in-memory size of the columns read (SelectedBytes), which for state columns is not their size on disk.

SYSTEM FLUSH LOGS;

SELECT
    replaceOne(log_comment, 'topn ', '')                              AS probe,
    count()                                                           AS runs,
    median(query_duration_ms)                                         AS median_ms,
    min(query_duration_ms)                                            AS min_ms,
    any(read_rows)                                                    AS read_rows,
    formatReadableSize(any(ProfileEvents['ReadCompressedBytes']))     AS read_from_disk,
    formatReadableSize(any(ProfileEvents['CompressedReadBufferBytes'])) AS decompressed,
    formatReadableSize(any(read_bytes))                               AS read_bytes_in_memory,
    formatReadableSize(max(memory_usage))                             AS peak_memory
FROM system.query_log
WHERE type = 'QueryFinish' AND log_comment LIKE 'topn %'
GROUP BY log_comment
ORDER BY min(event_time_microseconds);
