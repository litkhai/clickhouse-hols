-- Indexer: writes the base table. ai_reader: the guide's read-only user, granted the view only.
-- __INDEXER_PASSWORD__ and __AI_PASSWORD__ are replaced by run.sh with per-run random values.
CREATE USER IF NOT EXISTS indexer IDENTIFIED WITH sha256_password BY '__INDEXER_PASSWORD__';
GRANT SELECT, INSERT ON fileidx.file_index TO indexer;

CREATE USER IF NOT EXISTS ai_reader IDENTIFIED WITH sha256_password BY '__AI_PASSWORD__'
SETTINGS readonly = 1,
         max_result_rows = 20000,
         max_execution_time = 25,
         max_memory_usage = 4000000000;

GRANT SELECT ON fileidx.files TO ai_reader;   -- the view only, never the base table
