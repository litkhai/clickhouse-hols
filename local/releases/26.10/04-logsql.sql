-- ClickHouse 26.10 — the LogsQL dialect (experimental)
--
--   SET enable_logsql_dialect = 1, logsql_table = 'logs', dialect = 'logsql';
--   error | stats by (host) count() as n
--
-- LogsQL is the query language of VictoriaLogs: a filter, then pipes. 26.10 can
-- parse it and translate it, at parse time, into an ordinary SELECT over one
-- configured table. The time and message fields are columns named by
-- logsql_time_column and logsql_message_column, _time and _msg by default.
--
-- The question worth a lab is not whether it parses — it does, for everything
-- here — but what the translation reads. Measured on 26.10.3.7 over 2 million
-- rows with a text index on _msg:
--
--   * a _time range prunes by the primary key: 8,192 rows read
--   * every text filter reads all 2,000,000 rows, text index or not, because a
--     word becomes match(ifNull(toString(_msg), ''), '<token-boundary regex>'),
--     which no index can answer
--   * the same word as SQL hasToken reads 163,840 rows through the index
--
-- So: put a time range in every LogsQL query, and keep hot lookups in SQL.

SELECT '════════ 1. A log table with a text index ════════' AS section;

DROP DATABASE IF EXISTS lq;
CREATE DATABASE lq;

CREATE TABLE lq.logs
(
    _time  DateTime,
    host   LowCardinality(String),
    level  LowCardinality(String),
    status UInt16,
    _msg   String,
    INDEX msg_idx _msg TYPE text(tokenizer = 'splitByNonAlpha') GRANULARITY 1
)
ENGINE = MergeTree ORDER BY _time;

-- One line a second for 23 days. Twenty of them, one every 100,000 rows, are a
-- rare error whose words appear nowhere else.
INSERT INTO lq.logs
SELECT toDateTime('2026-10-26 00:00:00') + number,
       ['web-1', 'web-2', 'db-1'][number % 3 + 1],
       if(number % 100000 = 7, 'error', ['info', 'info', 'warn'][number % 3 + 1]),
       if(number % 100000 = 7, 507, [200, 200, 404][number % 3 + 1]),
       if(number % 100000 = 7,
          concat('disk quota exceeded on volume ', toString(number)),
          concat('GET /api/orders id=', toString(number)))
FROM numbers(2000000);

OPTIMIZE TABLE lq.logs FINAL;

SELECT '════════ 2. LogsQL ════════' AS section;

-- The condition cache would make every repeat look cheap (section 4 uses that).
-- Off for the measurements.
--
-- No comments between the LogsQL lines below: in this dialect a comment becomes
-- part of the next query's text in query_log. The last four return rows rather
-- than counts because their reads are compared in section 3, and a bare count()
-- can be answered from an index without reading rows at all.
SET enable_logsql_dialect = 1, logsql_database = 'lq', logsql_table = 'logs',
    use_query_condition_cache = 0, log_comment = 'lq_measure';
SET dialect = 'logsql';

quota | stats count() as n;
level:error | stats by (host) count() as n | sort by (host);
status:>=500 | stats by (status) count() as n;
"disk quota" | fields _time, host, _msg | sort by (_time) | limit 3;
{host="db-1"} level:error | count();
_time:[2026-10-26T01:00:00Z, 2026-10-26T02:00:00Z) | count();
quota | fields _time;
_time:[2026-10-26T01:00:00Z, 2026-10-26T02:00:00Z) | fields _time;
i(QUOTA) | fields _time;
*uota* | fields _time;

SET dialect = 'clickhouse';

SELECT _time FROM lq.logs WHERE hasToken(_msg, 'quota') FORMAT Null;

SYSTEM FLUSH LOGS query_log;

SELECT '════════ 3. What each one read ════════' AS section;

SELECT query, result_rows, read_rows
FROM (
    SELECT * FROM system.query_log
    WHERE log_comment = 'lq_measure' AND type = 'QueryFinish'
      AND (query LIKE '%| fields _time;' OR query LIKE 'SELECT _time FROM lq.logs%')
    ORDER BY event_time_microseconds DESC
    LIMIT 1 BY query
)
ORDER BY read_rows, query;

SELECT '════════ 4. The translation, from the condition cache ════════' AS section;

-- The translated SELECT is not logged. The query condition cache logs the
-- predicate it skips granules for, though, so run the word filter twice with the
-- cache on and read the predicate back from text_log.
SET use_query_condition_cache = 1, log_comment = 'lq_translate';
SET dialect = 'logsql';
quota | fields _time | limit 1;
quota | fields _time | limit 1;
SET dialect = 'clickhouse';

SYSTEM FLUSH LOGS text_log, query_log;

SELECT DISTINCT extract(message, 'for WHERE condition (.*)\\.$') AS translated_predicate
FROM system.text_log
WHERE query_id IN (SELECT query_id FROM system.query_log WHERE log_comment = 'lq_translate')
  AND message LIKE 'Query condition cache has dropped % for WHERE condition %';
