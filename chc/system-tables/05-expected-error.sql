-- 05 — A query that fails on purpose (run.sh expects the error)
SELECT toDate('not a date') SETTINGS log_comment = 'lab:q-error';
