-- errors/01-append-incremental.sql: REFRESH ... APPEND INCREMENTAL arrived in 26.9 (ClickHouse PR #114152).
-- On a 26.8 service the statement does not parse (Code 62, SYNTAX_ERROR at INCREMENTAL).
-- local/26.9-append-incremental.sql shows what it does on 26.9.
CREATE MATERIALIZED VIEW snapdiff.inc_rmv
REFRESH EVERY 1 HOUR APPEND INCREMENTAL TO snapdiff.changes
AS SELECT * FROM snapdiff.changes;
