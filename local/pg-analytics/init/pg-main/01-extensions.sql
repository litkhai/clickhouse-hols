-- pg-main, database :ILM_DB. Run by runner/setup.py with psql variables
-- rest_host / writer_id / writer_secret taken from .state/polaris.json.
CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_clickhouse;

-- pg_lake talks to Polaris as ilm_writer. catalog = 'rest' tables are then
-- registered as <database>.<schema>.<table>, i.e. warehouse ilm, namespace tpch.
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_host = :'rest_host';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_client_id = :'writer_id';
ALTER SYSTEM SET pg_lake_iceberg.rest_catalog_client_secret = :'writer_secret';
-- keep a week of snapshots: external readers may still be planning against an older one
ALTER SYSTEM SET pg_lake_iceberg.max_snapshot_age = 604800;
SELECT pg_reload_conf();

SELECT extname, extversion FROM pg_extension
WHERE extname IN ('pg_lake', 'pg_lake_iceberg', 'pg_lake_table', 'pg_clickhouse') ORDER BY 1;
